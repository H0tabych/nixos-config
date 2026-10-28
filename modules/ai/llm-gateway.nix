# Фича: llm-gateway · Слот: — · Домен: ai · Классы: N+H · Для: пользователей с capability ml
# Контракт: AI_SUBSYSTEM.md §3.3 (AI-GW-1…13), раздел 4 (роли), SEC-4/SEC-7.
# N-класс (этот хост) владеет секретами и рендером config.json для КАЖДОГО
# пользователя с capability `ml` (пересечение config.my.host.users ∩
# capabilities, по образцу modules/base/users.nix) — вынесено в
# _llm-gateway-secrets.nix (STR-6). H-класс (DESK-4, тонкая обёртка) — сам
# user-юнит: читает путь рендера через `osConfig` (AI_SUBSYSTEM.md §10 п.7),
# порт — через явный uid пользователя (п.8 того же списка, AI-GW-1).
# Реализация — Bifrost (_llm-gateway-package.nix, Приложение P.1 AI_SUBSYSTEM.md).
# Два sops-рендера на пользователя: config.json (для -app-dir юнита, через
# LoadCredential) и файл с готовым ключом доступа для клиентов. Значения
# секретов — прямо в config.json (обоснование и обязательный префикс "sk-bf-"
# — в шапке _llm-gateway-config.nix). AI-CMP-4: machine.d получает только URL и
# ПУТЬ к ключу доступа (AI_GATEWAY_ACCESS_KEY_FILE) — значения там нет
# (SEC-4/A3), само значение читает клиент редактора из файла.
# AI-GW-10 (запуск по требованию) здесь не реализован: не подтверждено, что
# бинарник Bifrost поддерживает systemd socket-activation (LISTEN_FDS); юнит
# всегда запущен на graphical-session.target, как swayosd-server
# (osd-swayosd.nix) — известное отступление, не блокирует AI-A6/9/14.
# StateDirectory в user-юните — ПРОВЕРИТЬ первым запуском (подтверждено живым
# запуском 2026-10-29: путь — ~/.local/state/llm-gateway/, работает).
# Известное ограничение (найдено 2026-10-29): изменение секрета/config.json
# не перезапускает юнит автоматически — sops.templates.restartUnits перезапускает
# системные юниты от root, а llm-gateway — user-юнит в сессии пользователя;
# после правки секретов/cloudRoles нужен ручной `systemctl --user restart
# llm-gateway`. Автоматизировать (например, через ExecStartPre-проверку
# контрольной суммы рендера) — не в этом шаге.
# Зависимости: ai-facts (my.ai.local, my.ai.gateway.*), host-facts (my.host.users),
# users (my.users.*.capabilities/uid) — только чтение my.*, не импорт (ARCH-3).
{ config, lib, ... }:
let
  outer = config;
  secretsFile = outer.flake.lib.repo.secrets;
  buildConfig = import ./_llm-gateway-config.nix { inherit lib; };

  knownProviders = [
    "openai"
    "anthropic"
    "bedrock"
    "cohere"
    "azure"
    "vertex"
    "mistral"
    "groq"
    "gemini"
    "deepseek"
    "cerebras"
    "perplexity"
    "openrouter"
  ];
in
{
  flake.modules.nixos.llm-gateway =
    { config, ... }:
    let
      gw = config.my.ai.gateway;
      mlUsers = lib.filter (u: lib.elem "ml" outer.my.users.${u}.capabilities) config.my.host.users;
      ph = name: config.sops.placeholder.${name};

      rendered = import ./_llm-gateway-secrets.nix {
        inherit
          lib
          secretsFile
          buildConfig
          mlUsers
          gw
          ;
        localRoles = config.my.ai.local;
        inference = config.my.ai.inference;
      };
    in
    {
      assertions = [
        {
          assertion = lib.all (r: lib.elem r.provider knownProviders) (lib.attrValues gw.cloudRoles);
          message = "my.ai.gateway.cloudRoles.*.provider должен быть известным Bifrost провайдером (transports/config.schema.json, Приложение P.1 AI_SUBSYSTEM.md).";
        }
      ];

      sops.secrets = rendered.mkSecrets;
      sops.templates = rendered.mkTemplates ph;
    };

  flake.modules.homeManager.llm-gateway =
    {
      config,
      osConfig,
      pkgs,
      ...
    }:
    let
      user = config.home.username;
      uid = osConfig.users.users.${user}.uid;
      port = osConfig.my.ai.gateway.portBase + (uid - 1000);
      pkg = pkgs.callPackage ./_llm-gateway-package.nix { };
      configPath = osConfig.sops.templates."llm-gw-config-${user}".path;
      # Не sops.secrets напрямую: клиентам нужен ключ с префиксом sk-bf-, который
      # добавляет Nix при рендере (_llm-gateway-secrets.nix) — иначе шлюз
      # подменяет ключ своим и отвечает access_not_found.
      accessKeyPath = osConfig.sops.templates."llm-gw-access-key-${user}".path;
    in
    {
      systemd.user.services.llm-gateway = {
        Unit = {
          Description = "llm-gateway (AI_SUBSYSTEM.md §3.3, Bifrost)";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          LoadCredential = "config.json:${configPath}";
          StateDirectory = "llm-gateway";
          ExecStartPre = "${pkgs.coreutils}/bin/install -m 0400 %d/config.json %S/llm-gateway/config.json";
          ExecStart = "${pkg}/bin/bifrost-http -host 127.0.0.1 -port ${toString port} -app-dir %S/llm-gateway";
          Restart = "on-failure";
          RestartSec = 2;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      # AI-CMP-4: только URL и путь к ключу — значения нет (SEC-4/A3).
      home.file.".config/machine.d/ai-gateway-env".text = ''
        # Сгенерировано Nix (llm-gateway, AI-CMP-4) — не редактируйте руками.
        export AI_GATEWAY_URL="http://127.0.0.1:${toString port}"
        export AI_GATEWAY_ACCESS_KEY_FILE="${accessKeyPath}"
      '';
    };
}
