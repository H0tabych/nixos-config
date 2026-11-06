# Приватная часть: llm-gateway · Владелец: modules/ai/llm-gateway.nix (STR-6)
# Чистая функция: описание системной службы шлюза одного пользователя (ADR-45,
# AI-GW-1). Отдельным файлом — чтобы тот же юнит собирал и ВМ-тест
# (tests/llm-gateway.nix) с обычными файлами вместо секретов sops.
#
# Секреты. Файлы провайдеров принадлежат root (0400) и доходят до службы только через
# LoadCredential — ни пользователь, ни агент их не читают (AI-A6). Ключи доступа
# (по паре «агент × режим») и учётные данные управляющего API служба генерирует сама
# и хранит в своём состоянии (/var/lib/private/…, 0700, DynamicUser): они постоянны
# (переживают перезапуск; ротация — удалить файл и перезапустить). Пользователю
# публикуются копии лишь ключей доступа: /run/llm-gateway/<user>/<агент>-<режим>,
# root:<группа пользователя> 0440 — в песочницу этот каталог не попадает (корень
# строится из разрешённого, AI-SBX-1). Копию делает ExecStartPre с «+» (от root).
#
# Рендер конфига. Шаблон конфига (соседняя приватная часть) содержит метки `@ИМЯ@`; при старте
# jq подставляет значения (литерально, без спецсимволов sed). Провайдер с пустым или
# отсутствующим секретом вычёркивается вместе с его правилами и правами ключей —
# юнит не `failed` без облачных ключей (AI-GW-9, AI-A14).
# AI-GW-10 (запуск по требованию) не реализован: не подтверждено, что Bifrost умеет
# socket-activation — известное отступление, как и раньше.
{
  lib,
  pkgs,
  pkg, # bifrost-http
  user,
  group,
  port,
  template, # attrset — шаблон конфига шлюза
  providers, # my.ai.gateway.providers: id → { type, … } (имя в конфиге шлюза — тип)
  keyIds, # id ключей доступа: "<агент>-<режим>"
  credPath, # id провайдера → путь к файлу секрета
  extraEnvironment ? { },
}:
let
  unit = "llm-gateway-${user}";
  providerIds = lib.attrNames providers;
  templateFile = pkgs.writeText "${unit}.json" (builtins.toJSON template);
  bins = lib.makeBinPath [
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.jq
  ];

  # Подстановка меток: одна переменная jq на секрет (имена — по индексу).
  keyVars = lib.imap0 (i: id: {
    var = "k${toString i}";
    mark = "@KEY_${id}@";
    inherit id;
  }) keyIds;
  provVars = lib.imap0 (i: id: {
    var = "p${toString i}";
    mark = "@PROVIDER_${id}@";
    inherit id;
  }) providerIds;
  adminVars = [
    {
      var = "au";
      mark = "@ADMIN_USER@";
    }
    {
      var = "ap";
      mark = "@ADMIN_PASS@";
    }
  ];
  allVars = keyVars ++ provVars ++ adminVars;
  substitute = lib.concatMapStringsSep " | " (
    v: "sub(\"${v.mark}\"; (" + "$" + v.var + " | rtrimstr(\"\\n\")))"
  ) allVars;

  filter = pkgs.writeText "${unit}.jq" ''
    def alive($p): ($dead | index($p) | not);
    .providers |= with_entries(select(.key as $k | alive($k)))
    | .governance.routing_rules |= map(select(all(.targets[]; alive(.provider))))
    | .governance.virtual_keys |= map(.provider_configs |= map(select(alive(.provider))))
    | walk(if type == "string" then ${substitute} else . end)
  '';

  prepare = pkgs.writeShellScript "${unit}-prepare" ''
    set -eu
    export PATH=${bins}
    umask 077
    state=$STATE_DIRECTORY
    mkdir -p "$state/keys"

    # Постоянные ключи: создаются один раз (AI-GW-3).
    gen() {
      [ -s "$state/keys/$1" ] || printf '%s%s' "$2" \
        "$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')" > "$state/keys/$1"
    }
    ${lib.concatMapStringsSep "\n" (id: "gen ${lib.escapeShellArg id} sk-bf-") keyIds}
    gen admin-user adm-
    gen admin-pass ""

    args=(
      ${lib.concatMapStringsSep "\n      " (v: "--rawfile ${v.var} \"$state/keys/${v.id}\"") keyVars}
      --rawfile au "$state/keys/admin-user"
      --rawfile ap "$state/keys/admin-pass"
    )
    dead=()
    ${lib.concatMapStringsSep "\n" (v: ''
      cred="$CREDENTIALS_DIRECTORY/provider-${v.id}"
      if [ -s "$cred" ] && grep -q '[^[:space:]]' "$cred"; then
        args+=(--rawfile ${v.var} "$cred")
      else
        args+=(--arg ${v.var} "")
        dead+=(${lib.escapeShellArg providers.${v.id}.type})
        echo "llm-gateway: нет ключа провайдера ${v.id} — его роли недоступны (AI-GW-9)" >&2
      fi
    '') provVars}
    deadjson=$(jq -cn '$ARGS.positional' --args ''${dead[@]+"''${dead[@]}"})

    jq "''${args[@]}" --argjson dead "$deadjson" -f ${filter} ${templateFile} \
      > "$state/config.json.new"
    mv "$state/config.json.new" "$state/config.json"
  '';

  # От root («+»): копии ключей доступа — пользователю, больше ничего.
  publish = pkgs.writeShellScript "${unit}-publish" ''
    set -eu
    export PATH=${bins}
    src=/var/lib/private/${unit}/keys
    dst=/run/llm-gateway/${user}
    install -d -m 0755 -o root -g root /run/llm-gateway
    install -d -m 0750 -o root -g ${lib.escapeShellArg group} "$dst"
    ${lib.concatMapStringsSep "\n" (
      id: "install -m 0440 -o root -g ${lib.escapeShellArg group} \"$src/${id}\" \"$dst/${id}\""
    ) keyIds}
  '';

  unpublish = pkgs.writeShellScript "${unit}-unpublish" ''
    rm -rf /run/llm-gateway/${lib.escapeShellArg user}
  '';
in
{
  description = "llm-gateway для ${user} (AI_SUBSYSTEM.md §3.3, ADR-45, Bifrost)";
  wantedBy = [ "multi-user.target" ];
  after = [ "network.target" ];
  unitConfig.StartLimitIntervalSec = 0;
  restartTriggers = [
    templateFile
    filter
    prepare
  ];
  environment = extraEnvironment;
  serviceConfig = {
    DynamicUser = true;
    StateDirectory = unit;
    StateDirectoryMode = "0700";
    LoadCredential = map (id: "provider-${id}:${credPath id}") providerIds;
    ExecStartPre = [
      "${prepare}"
      "+${publish}"
    ];
    ExecStart = "${pkg}/bin/bifrost-http -host 127.0.0.1 -port ${toString port} -app-dir %S/${unit}";
    ExecStopPost = "+${unpublish}";
    # Первый старт без сети (справочник цен грузится с сайта апстрима, пока нет кэша
    # в состоянии) — повторять, а не превращаться в `failed` (AI-GW-9).
    Restart = "on-failure";
    RestartSec = 5;
    # AI-GW-1, AI-GW-13: минимум прав.
    ProtectHome = true;
    ProtectSystem = "strict";
    PrivateTmp = true;
    PrivateDevices = true;
    NoNewPrivileges = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    CapabilityBoundingSet = "";
    SystemCallArchitectures = "native";
  };
}
