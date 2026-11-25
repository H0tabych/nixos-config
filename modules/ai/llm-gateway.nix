# Фича: llm-gateway · Слот: — · Домен: ai · Классы: N · Для: пользователей с capability ml
# Контракт: AI_SUBSYSTEM.md §3.3 (AI-GW-1…14), раздел 4 (роли), ADR-45, SEC-4/SEC-7.
# Системная служба шлюза на КАЖДОГО пользователя с capability `ml` (пересечение
# config.my.host.users ∩ capabilities, по образцу modules/base/users.nix): ключи доступа по паре
# «агент × режим» генерирует служба, пользователь читает лишь файлы своих ключей
# (_llm-gateway-service.nix). Порт — portBase + (uid − 1000), uid явный (фича users, AI-GW-1).
# Шлюз — MCP-вход агентов (AI-GW-14) и локальные роли инференса (AI-GW-2); облачных провайдеров и
# посредничества между агентом и его моделью в нём нет (ADR-051): агенты ходят к моделям сами, в
# родных протоколах.
# Реализация — Bifrost (_llm-gateway-package.nix, Приложение P.1 AI_SUBSYSTEM.md);
# политика хоста → шаблон конфига: _llm-gateway-config.nix. Справочник цен моделей Bifrost —
# пустой файл из хранилища: с сайта поставщика шлюз его не качает (AI-GW-13).
# AI-CMP-4: машинный слой пользователя получает только URL и КАТАЛОГ с файлами
# ключей — значений там нет (SEC-4/A3); файл пишется из этого nixos-модуля через
# home-manager.users (прецедент — modules/base/users.nix), поэтому HM-части у фичи нет.
# AI-GW-10 (запуск по требованию) не реализован — см. _llm-gateway-service.nix.
# MCP-шлюз (AI-GW-14, R9.23): серверы с секретом и удалённые — `my.ai.gateway.mcp` (политика
# хоста), права ключей — `my.ai.gateway.agents.<агент>.mcp` (только `online`); определения —
# _llm-gateway-mcp.nix. Секрет сервера — `ai.gateway.mcpToken.<id>` в sops пользователя.
# Зависимости: ai-facts (my.ai.*), host-facts (my.host.users), users
# (my.users.*.capabilities) — только чтение my.*, не импорт (ARCH-3).
{ config, lib, ... }:
let
  outer = config;
  secretsFile = outer.flake.lib.repo.secrets;
  buildConfig = import ./_llm-gateway-config.nix { inherit lib; };
  mcpNeutralId = lib.match "[a-z][a-z0-9-]*"; # имя клиента MCP не начинается с цифры (Bifrost)

  modes = [
    "online"
    "offline"
  ];
  neutralId = lib.match "[a-z0-9][a-z0-9-]*";
in
{
  flake.modules.nixos.llm-gateway =
    { config, pkgs, ... }:
    let
      gw = config.my.ai.gateway;
      mlUsers = lib.filter (u: lib.elem "ml" outer.my.users.${u}.capabilities) config.my.host.users;
      pkg = pkgs.callPackage ./_llm-gateway-package.nix { };
      mcpBuild = import ./_llm-gateway-mcp.nix { inherit lib pkgs; } {
        policy = gw.mcp;
        inherit (gw) agents;
      };
      keyIds = lib.concatMap (a: map (m: "${a}-${m}") modes) (lib.attrNames gw.agents);
      unitOf = user: "llm-gateway-${user}";
      # Справочник цен моделей Bifrost — пустой: цены и бюджеты шлюзу не нужны (ADR-051), а
      # загрузка справочника с сайта поставщика запрещена (AI-GW-13).
      pricingFile = pkgs.writeText "llm-gateway-pricing.json" "{}";
      template = buildConfig {
        inherit (gw) agents;
        inherit (config.my.ai) inference;
        localRoles = config.my.ai.local;
        mcp = mcpBuild;
        pricingUrl = "file://${pricingFile}";
      };
      # Источник секрета сервера MCP-шлюза: файл в домашнем каталоге пользователя (решение
      # владельца) либо sops. Копирует в состояние службы root перед стартом (_llm-gateway-service).
      mcpSrc =
        user:
        map (
          s:
          s
          // {
            src =
              if s.homeFile != null then
                "${config.users.users.${user}.home}/${s.homeFile}"
              else
                config.sops.secrets."ai.gateway.mcpToken.${s.id}.${user}".path;
          }
        ) mcpBuild.secrets;
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
          group = config.users.users.${user}.group;
          port = gw.portBase + (config.users.users.${user}.uid - 1000);
          mcpSecrets = mcpSrc user;
        };
    in
    {
      assertions = [
        {
          assertion = lib.all (id: neutralId id != null) keyIds;
          message = "my.ai.gateway.agents: имена агентов — [a-z0-9-], без имён вендоров (SEC-3).";
        }
        {
          assertion = lib.all (id: mcpNeutralId id != null) (lib.attrNames gw.mcp);
          message = "my.ai.gateway.mcp: id сервера — [a-z][a-z0-9-]*, без имён вендоров (SEC-3).";
        }
        {
          assertion = lib.all (
            s:
            if s.type == "stdio" then s.command != null && (!s.secret || s.secretEnv != null) else s.url != null
          ) (lib.attrValues gw.mcp);
          message = "my.ai.gateway.mcp: у stdio-сервера нужен command (и secretEnv при secret), у http — url.";
        }
        {
          assertion = lib.all (a: lib.all (id: gw.mcp ? ${id}) a.mcp) (lib.attrValues gw.agents);
          message = "my.ai.gateway.agents.*.mcp должен перечислять id из my.ai.gateway.mcp.";
        }
      ];

      sops.secrets = lib.listToAttrs (
        lib.concatMap (
          user:
          map (
            s:
            lib.nameValuePair "ai.gateway.mcpToken.${s.id}.${user}" {
              key = "ai.gateway.mcpToken.${s.id}";
              sopsFile = secretsFile "users/${user}.yaml";
              owner = "root";
              mode = "0400";
              restartUnits = [ "${unitOf user}.service" ];
            }
          ) (lib.filter (s: s.homeFile == null) mcpBuild.secrets)
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
