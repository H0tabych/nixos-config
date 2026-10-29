# Фича: agents-tools · Слот: — · Домен: ai · Классы: H · Для: пользователей с ml
# Контракт: AI_SUBSYSTEM.md §3.4 (AI-AGT-1…7, «Лаунчер-песочница» AI-SBX-1…11).
# Три роли (AI-AGT-1): claude-code (тяжёлый автономный), DeepSeek Harness
# (альтернативный автономный — другое семейство моделей), aider-chat
# (контролируемый). claude-code/aider-chat нет в nixpkgs-26.05 (ПРОВЕРЕНО
# `nix eval`) — точечно из pkgs.unstable (ARCH-14, прецедент nix-settings.nix).
# DeepSeek Harness нет вообще (ни 26.05, ни unstable) — своя деривация
# (_agents-tools-dsh-package.nix) с автозаменой на nixpkgs через `or`, как
# только пакет там появится (проверять `nix search` перед `flake update`).
# AI-AGT-4: единственный способ запуска агентов — agent-launcher; небёрнутые
# бинарники ролей в home.packages не попадают. AI-SBX-4: лаунчер активирует
# проектное окружение через уже существующий `direnv` (env-manager-direnv,
# R6.1) перед запуском — без повторной реализации активации окружения.
# AI-SBX-5: сетевые режимы online/offline принимаются флагом, но изоляции
# пространства имён сети пока нет — ПРОВЕРИТЬ (см. _agents-tools-sandbox.nix).
# Конфиг каждой роли — в dotfiles (AI-AGT-3), под ~/.config/<роль>/ (песочница
# возвращает ~/.config на чтение); путь до него передаётся agents-sandbox-exec
# явным --env (CLAUDE_CONFIG_DIR/DSH_HOME) либо аргументом бинарника (aider
# --config) — ПРОВЕРИТЬ точный механизм каждого приложения при живом прогоне.
# Роли из AI_SUBSYSTEM.md §4: claude → strong-autonomous, aider → local-chat
# (явный потребитель по таблице ролей), dsh → cost-autonomous (решение
# пользователя R8.5/R8.6). AI_SUBSYSTEM.md §2.5: ключ доступа к шлюзу
# «лаунчер кладёт его только в окружение агента» — значение читается из
# AI_GATEWAY_ACCESS_KEY_FILE здесь и уходит только в переменную окружения
# самого процесса агента (через --env), никогда на диск; при отсутствии
# шлюза у пользователя (AI-GW-9) роль просто не получает авторизации, а не
# падает. Для DeepSeek Harness точный механизм подстановки ключа/модели —
# ПРОВЕРИТЬ (dev preview, свой формат профиля, не переменные окружения
# OpenAI-стиля, насколько подтверждено по `dsh --help`).
# AI-SBX-7: перед входом в песочницу лаунчер через agents-git-isolate
# заводит агенту отдельный клон репозитория на отдельной ветке (не
# worktree — см. обоснование в _agents-tools-git-isolate.nix) и блокирует
# push pre-push-хуком по умолчанию; слияние — вручную, человеком.
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
      sandboxExec = pkgs.callPackage ./_agents-tools-sandbox.nix { };
      gitIsolate = pkgs.callPackage ./_agents-tools-git-isolate.nix { };

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
      dshRole = pickRole [
        "cost-autonomous"
        "strong-autonomous"
      ];

      claudeCode = pkgs.unstable.claude-code;
      aiderChat = pkgs.unstable.aider-chat;
      # ПРОВЕРИТЬ при каждом `flake update`: `nix search nixpkgs deepseek-harness`.
      # Как только пакет появится в канале (стабильном или unstable), `or`
      # сам начнёт использовать его — отдельная правка не нужна.
      deepseekHarness =
        pkgs.unstable.deepseek-harness or (pkgs.callPackage ./_agents-tools-dsh-package.nix { });

      agentLauncher = pkgs.callPackage ./_agents-tools-launcher.nix {
        inherit
          lib
          sandboxExec
          gitIsolate
          claudeCode
          deepseekHarness
          aiderChat
          aiderRole
          dshRole
          ;
      };
    in
    {
      assertions = [
        {
          assertion = aiderRole != null && dshRole != null;
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
