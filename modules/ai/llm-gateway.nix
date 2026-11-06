# Фича: llm-gateway · Слот: — · Домен: ai · Классы: N · Для: пользователей с capability ml
# Контракт: AI_SUBSYSTEM.md §3.3 (AI-GW-1…14), раздел 4 (роли), ADR-45, SEC-4/SEC-7.
# Системная служба шлюза на КАЖДОГО пользователя с capability `ml` (пересечение
# config.my.host.users ∩ capabilities, по образцу modules/base/users.nix): секреты
# провайдеров у root, ключи доступа по паре «агент × режим» генерирует служба,
# пользователь читает лишь файлы своих ключей (_llm-gateway-service.nix). Порт —
# portBase + (uid − 1000), uid явный (фича users, AI-GW-1).
# Реализация — Bifrost (_llm-gateway-package.nix, Приложение P.1 AI_SUBSYSTEM.md);
# политика хоста → шаблон конфига: _llm-gateway-config.nix.
# AI-CMP-4: машинный слой пользователя получает только URL и КАТАЛОГ с файлами
# ключей — значений там нет (SEC-4/A3); файл пишется из этого nixos-модуля через
# home-manager.users (прецедент — modules/base/users.nix), поэтому HM-части у фичи нет.
# Секреты в sops пользователя: `ai.gateway.providerKey.<id>` — по нейтральному id
# провайдера (SEC-3). Ключи доступа и учётные данные management-API в sops не хранятся.
# AI-GW-10 (запуск по требованию) не реализован — см. _llm-gateway-service.nix.
# MCP-шлюз (AI-GW-14) — R9.20: до него у всех ключей инструменты запрещены.
# Зависимости: ai-facts (my.ai.*), host-facts (my.host.users), users
# (my.users.*.capabilities), tunnel-facts (my.tunnel.*) — только чтение my.*, не импорт (ARCH-3).
{ config, lib, ... }:
let
  outer = config;
  secretsFile = outer.flake.lib.repo.secrets;
  buildConfig = import ./_llm-gateway-config.nix { inherit lib; };

  knownTypes = [
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
  ];
  neutralId = lib.match "[a-z0-9][a-z0-9-]*";
  modes = [
    "online"
    "offline"
  ];
in
{
  flake.modules.nixos.llm-gateway =
    { config, pkgs, ... }:
    let
      gw = config.my.ai.gateway;
      mlUsers = lib.filter (u: lib.elem "ml" outer.my.users.${u}.capabilities) config.my.host.users;
      pkg = pkgs.callPackage ./_llm-gateway-package.nix { };
      keyIds = lib.concatMap (a: map (m: "${a}-${m}") modes) (lib.attrNames gw.agents);
      providerIds = lib.attrNames gw.providers;
      allNative = lib.concatMap (p: p.nativeModels) (lib.attrValues gw.providers);
      unitOf = user: "llm-gateway-${user}";
      # NET-10: в M1 системная служба не получает переменных прокси сессии —
      # адрес берётся из единственного места, my.tunnel.local.http. В M2 трафик
      # идёт через туннель прозрачно.
      proxyUrl = lib.optionalString (
        config.my.tunnel.mode == "m1"
      ) "http://${config.my.tunnel.local.http.address}:${toString config.my.tunnel.local.http.port}";
      template = buildConfig {
        inherit (gw)
          providers
          agents
          budget
          cloudRoles
          ;
        inherit (config.my.ai) inference;
        localRoles = config.my.ai.local;
        proxyUrl = if proxyUrl == "" then null else proxyUrl;
      };
      mkService =
        user:
        import ./_llm-gateway-service.nix {
          inherit
            lib
            pkgs
            pkg
            user
            template
            keyIds
            ;
          inherit (gw) providers;
          group = config.users.users.${user}.group;
          port = gw.portBase + (config.users.users.${user}.uid - 1000);
          credPath = id: config.sops.secrets."ai.gateway.providerKey.${id}.${user}".path;
        };
    in
    {
      assertions = [
        {
          assertion = lib.all (p: lib.elem p.type knownTypes) (lib.attrValues gw.providers);
          message = "my.ai.gateway.providers.*.type должен быть прямым провайдером из списка Bifrost (агрегаторы отклонены, ADR-45; Приложение P.1 AI_SUBSYSTEM.md).";
        }
        {
          assertion =
            lib.length (lib.unique (map (p: p.type) (lib.attrValues gw.providers))) == lib.length providerIds;
          message = "my.ai.gateway.providers: тип провайдера у каждого id уникален — в конфиге шлюза провайдер называется по типу (_llm-gateway-config.nix).";
        }
        {
          assertion = lib.all (id: neutralId id != null) (providerIds ++ keyIds);
          message = "my.ai.gateway: id провайдеров и агентов — [a-z0-9-], без имён вендоров (SEC-3).";
        }
        {
          assertion = lib.all (r: gw.providers ? ${r.provider}) (lib.attrValues gw.cloudRoles);
          message = "my.ai.gateway.cloudRoles.*.provider должен быть id из my.ai.gateway.providers.";
        }
        {
          assertion = lib.all (a: a.nativeProvider == null || gw.providers ? ${a.nativeProvider}) (
            lib.attrValues gw.agents
          );
          message = "my.ai.gateway.agents.*.nativeProvider должен быть id из my.ai.gateway.providers.";
        }
        {
          assertion = lib.all (m: !(gw.cloudRoles ? ${m} || config.my.ai.local ? ${m})) allNative;
          message = "my.ai.gateway.providers.*.nativeModels не должны совпадать с именами ролей (сквозной маршрут и роли различаются по имени модели).";
        }
        {
          assertion = gw.cloudRoles == { } || gw.budget.maxUSD != null;
          message = "Облачным ролям нужен лимит расходов my.ai.gateway.budget.maxUSD (AI-GW-6).";
        }
      ];

      sops.secrets = lib.listToAttrs (
        lib.concatMap (
          user:
          map (
            id:
            lib.nameValuePair "ai.gateway.providerKey.${id}.${user}" {
              key = "ai.gateway.providerKey.${id}";
              sopsFile = secretsFile "users/${user}.yaml";
              owner = "root";
              mode = "0400";
              restartUnits = [ "${unitOf user}.service" ];
            }
          ) providerIds
        ) mlUsers
      );

      systemd.services = lib.listToAttrs (
        map (user: lib.nameValuePair (unitOf user) (mkService user)) mlUsers
      );

      # AI-CMP-4: только URL и каталог ключей — значений нет (SEC-4/A3).
      home-manager.users = lib.genAttrs mlUsers (user: {
        home.file.".config/machine.d/ai-gateway-env".text = ''
          # Сгенерировано Nix (llm-gateway, AI-CMP-4) — не редактируйте руками.
          export AI_GATEWAY_URL="http://127.0.0.1:${
            toString (gw.portBase + (config.users.users.${user}.uid - 1000))
          }"
          export AI_GATEWAY_KEYS_DIR="/run/llm-gateway/${user}"
        '';
      });
    };
}
