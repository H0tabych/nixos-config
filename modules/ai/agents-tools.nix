# Фича: agents-tools · Слот: — · Домен: ai · Классы: H · Для: пользователей с ml
# Контракт: AI_SUBSYSTEM.md §3.4 (AI-AGT-1…7, «Лаунчер-песочница» AI-SBX-1…11).
# Три роли (AI-AGT-1): claude-code (тяжёлый автономный), DeepSeek Harness
# (альтернативный автономный — другое семейство моделей), aider-chat
# (контролируемый). claude-code в nixpkgs-26.05 отстаёт — точечно из pkgs.unstable
# (ARCH-14, прецедент nix-settings.nix). aider-chat — из основного канала, версия та
# же; в unstable он с 2026-10-19 не вычисляется: зависимость posthog помечена broken
# при mcp >= 2 (ПРОВЕРЕНО `nix eval`, 2026-11-05).
# DeepSeek Harness в 26.05 нет, в unstable есть (0.2.1-rc.3, с обходом аддона
# `node-addon-require-builtin`) — берём оттуда, как claude-code (ARCH-14);
# собственной деривации больше нет (R9.18).
# R9.18 (AI-ROLE-5): `dsh` подключается переменными окружения
# (`DEEPSEEK_BASE_URL` — шлюз, `DEEPSEEK_API_KEY` — ключ доступа), ходит по
# собственным моделям провайдера, профили в `$DSH_HOME` лаунчер не пишет; политика
# Nix — патч из хранилища флагом `--patch` (_agents-tools-dsh-policy.nix).
# AI-AGT-4: единственный способ запуска агентов — agent-launcher; небёрнутые
# бинарники ролей в home.packages не попадают. AI-SBX-4: лаунчер активирует
# проектное окружение через уже существующий `direnv` (env-manager-direnv,
# R6.1) перед запуском — без повторной реализации активации окружения.
# AI-SBX-5 (ADR-44, R9.17): у песочницы свой сетевой netns; наружу — мосты
# `agents-net` (_agents-tools-net.nix): шлюз и, в online, HTTP-вход туннеля
# (my.tunnel.local.http; без туннеля на хосте — выхода нет). Режим по умолчанию —
# по корням рабочих деревьев `~/.config/ai/work-roots` и маркеру `.ai/offline`,
# облако — флагом `--online` на запуск. Порт веб-интерфейса dsh — на пользователя
# от `my.ai.gateway.portBase` (+100 + uid − 1000), чтобы не пересекаться со шлюзом.
# Конфиг каждой роли — в dotfiles (AI-AGT-3), под ~/.config/<роль>/. Песочница
# (AI-SBX-1/2, R9.14) собирает корень из разрешённого и возвращает из ~/.config
# только белый список (machine.d, ai, git, direnv) и каталоги роли (`--config`),
# только чтение; остальной ~/.config, в т.ч. ключ расшифровки, не виден.
# Роли из AI_SUBSYSTEM.md §4: claude — по подписке, aider → local-chat
# (явный потребитель по таблице ролей); dsh ролей не использует — сквозной
# маршрут собственных моделей провайдера (AI-ROLE-5). AI_SUBSYSTEM.md §2.5: ключ доступа к шлюзу
# «лаунчер кладёт его только в окружение агента» — значение читается из
# AI_GATEWAY_ACCESS_KEY_FILE здесь и уходит только в переменную окружения
# самого процесса агента (через --pass-env), никогда на диск; при отсутствии
# шлюза у пользователя (AI-GW-9) роль просто не получает авторизации, а не
# падает. Для DeepSeek Harness ключ — `DEEPSEEK_API_KEY` (ПРОВЕРЕНО 2026-11-07
# перехватом запроса: заголовок `x-api-key`, путь `<база>/v1/messages`).
# AI-SBX-7 (ADR-44): работа на месте. Агент работает в текущем дереве проекта
# и коммитит; метаданные git (config, hooks, info, `.envrc`) в песочнице только
# на чтение, общий git-каталог привязан к себе, `.direnv` у роли свой
# (_agents-tools-sandbox.nix). После сессии лаунчер печатает отчёт
# (_agents-tools-git.nix): сдвинутые ссылки, флаги индекса,
# вложенные репозитории, изменённые игнорируемые файлы. Слияние и публикация —
# только человек.
# Зависимости: нет импорта фич (ARCH-3); `direnv` берётся как пакет через
# pkgs.direnv, активация — дело env-manager-direnv на хосте (FEAT-8).
_: {
  flake.modules.homeManager.agents-tools =
    {
      pkgs,
      lib,
      osConfig,
      ...
    }:
    let
      gitTool = pkgs.callPackage ./_agents-tools-git.nix { };
      netTool = pkgs.callPackage ./_agents-tools-net.nix { };
      sandboxExec = pkgs.callPackage ./_agents-tools-sandbox.nix { inherit gitTool netTool; };
      # Порт HTTP-входа туннеля (мост `proxy`); null — на хосте нет туннеля.
      tunnelHttpPort = lib.attrByPath [ "my" "tunnel" "local" "http" "port" ] null osConfig;
      dshWebPortBase = osConfig.my.ai.gateway.portBase + 100;

      # Имя роли для каждого агента берётся из политики хоста, а не пишется
      # строкой здесь: иначе в лаунчер попадает роль, которой на хосте нет, и
      # шлюз отвечает «could not auto resolve a provider» уже в рантайме
      # (ПРОВЕРЕНО живьём: так и было с `strong-autonomous` и `local-chat`).
      # Доступные роли — облачные из `my.ai.gateway.cloudRoles` плюс локальные
      # из `my.ai.local` (их заполняет фича инференса по VRAM хоста).
      available =
        (lib.attrNames osConfig.my.ai.gateway.cloudRoles) ++ (lib.attrNames osConfig.my.ai.local);
      # Первая существующая роль из списка предпочтений; пусто — если нет ни
      # одной (тогда срабатывает assertion ниже, на сборке, а не в рантайме).
      pickRole = lib.findFirst (r: lib.elem r available) null;
      # AI_SUBSYSTEM.md раздел 4: контролируемой роли положена local-chat;
      # если её на хосте нет — fallback на cost-autonomous (AI-ROLE-3:
      # заранее заданный fallback, а не тишина). Тяжёлая роль роли шлюза не
      # получает вовсе — она ходит по своей подписке (AI-GW-11, см. лаунчер).
      aiderRole = pickRole [
        "local-chat"
        "cost-autonomous"
      ];

      claudeCode = pkgs.unstable.claude-code;
      aiderChat = pkgs.aider-chat;
      # Версия — из закреплённого unstable (ПРОВЕРИТЬ политику при каждом обновлении:
      # `dsh --dump-config`, список записей в _agents-tools-dsh-policy.nix).
      deepseekHarness = pkgs.unstable.deepseek-harness;

      # Политика Nix для dsh (поиск, телеметрия, менеджер плагинов) — в хранилище.
      dshPolicy = pkgs.callPackage ./_agents-tools-dsh-policy.nix { };

      agentLauncher = pkgs.callPackage ./_agents-tools-launcher.nix {
        inherit
          lib
          sandboxExec
          netTool
          tunnelHttpPort
          dshWebPortBase
          gitTool
          claudeCode
          deepseekHarness
          aiderChat
          aiderRole
          dshPolicy
          ;
      };
    in
    {
      assertions = [
        {
          assertion = aiderRole != null;
          message =
            "agents-tools: у хоста нет ни одной роли, пригодной для агентов. "
            + "Объявите хотя бы `cost-autonomous` в my.ai.gateway.cloudRoles "
            + "(AI_SUBSYSTEM.md раздел 4). Сейчас доступны: "
            + lib.concatStringsSep ", " available;
        }
      ];

      home.packages = [ agentLauncher ];
    };
}
