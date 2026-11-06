# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Лаунчер ролей (AI-AGT-4: единственный способ запуска агентов). Отделён от
# фичи по границе контракта (STR-5): фича владеет составом ролей и пакетами,
# этот файл — тем, как роль превращается в вызов внутри песочницы
# (её даёт владелец аргументом `sandboxExec`). Обоснования по роли — в комментариях
# ниже и в шапке владельца.
{
  pkgs,
  lib,
  sandboxExec,
  gitIsolate,
  claudeCode,
  deepseekHarness,
  aiderChat,
  aiderRole,
  dshProfile,
}:
pkgs.writeShellApplication {
  name = "agent-launcher";
  runtimeInputs = [
    pkgs.direnv
    sandboxExec
    gitIsolate
  ];
  text = ''
    usage() {
      echo "usage: agent-launcher <claude|dsh|aider> [--offline] [-- args...]" >&2
      exit 1
    }
    [ "$#" -ge 1 ] || usage
    role=$1
    shift

    mode=online
    if [ "''${1:-}" = "--offline" ]; then
      mode=offline
      shift
    fi
    [ "''${1:-}" = "--" ] && shift

    # Адрес шлюза и путь к ключу — из машинного слоя (DOT-5, AI-CMP-4), а не
    # из того, что досталось интерактивной сессии: файл пишет фича
    # llm-gateway, но `.zshrc` его не подключает (ПРОВЕРЕНО: AI_GATEWAY_URL в
    # сессии пуст, из-за чего агенты уходили мимо шлюза). Берём сами, не
    # перекрывая уже заданное в окружении.
    if [ -z "''${AI_GATEWAY_URL:-}" ] && [ -r "$HOME/.config/machine.d/ai-gateway-env" ]; then
      # shellcheck source=/dev/null  # файл машинного слоя, вне сборки
      . "$HOME/.config/machine.d/ai-gateway-env"
    fi

    # Ключ доступа к шлюзу (AI-SBX-3): читается здесь, снаружи песочницы, и
    # уходит ТОЛЬКО значением в окружение процесса агента — через
    # `--pass-env` (из окружения этого процесса, не из argv), никогда в файл/лог.
    # Путь к файлу с ключом внутрь не пробрасывается: там его всё равно нет.
    gw_key=""
    if [ -n "''${AI_GATEWAY_ACCESS_KEY_FILE:-}" ] && [ -r "$AI_GATEWAY_ACCESS_KEY_FILE" ]; then
      gw_key=$(cat "$AI_GATEWAY_ACCESS_KEY_FILE")
    fi
    # Из окружения самого лаунчера путь не нужен дальше — не тащим его в `env`.
    unset AI_GATEWAY_ACCESS_KEY_FILE

    # extra_env — доплата к белому списку agents-sandbox-exec (--env,
    # AI-SBX-3): пути и адреса под именами, которые понимает приложение.
    # Ключ шлюза идёт отдельно, через export + `--pass-env` (см. ниже).
    # extra_bin_args — то же там, где приложение берёт значение только
    # аргументом командной строки. $HOME здесь — настоящий домашний каталог:
    # agent-launcher выполняется до входа в песочницу.
    state_dir="$HOME/.local/state/agents/$role"
    # AI-SBX-7: если $PWD внутри git-репозитория, агент получает отдельный
    # клон на отдельной ветке вместо прямого доступа к чекауту пользователя
    # (agents-git-isolate — та же логика для всех ролей, вынесена отдельно от
    # per-role case ниже, т.к. не зависит от роли, кроме имени ветки).
    # Сообщения о клоне/ветке идут в stderr и видны пользователю сразу.
    project_dir=$(agents-git-isolate "$role" "$state_dir" "$PWD")

    extra_env=()
    extra_bin_args=()
    sandbox_opts=()
    # Каталоги роли в ~/.config (белый список AI-SBX-2, только чтение).
    case "$role" in
      claude)
        bin=${lib.getExe claudeCode}
        # CLAUDE_CONFIG_DIR НЕ подменяем. У claude-code один каталог на всё:
        # настройки, список MCP-серверов, плагины, скиллы, сессии по проектам
        # и собственная авторизация — то есть ровно «каталог приложения»
        # (AI_SUBSYSTEM.md §2.5, класс D). Подмена каталога на свежий
        # означала бы, что агент не видит ни своих MCP, ни прошлых сессий —
        # ПРОВЕРЕНО живьём: именно так и получилось, пока здесь стоял
        # CLAUDE_CONFIG_DIR в state_dir (данные при этом не терялись, они
        # остаются в ~/.claude).
        # Решение пользователя (2026-10-29): тяжёлой роли нужен доступ ко
        # всему домашнему каталогу на запись — соседние репозитории, заметки,
        # кросс-проектные правки. Поэтому именно она идёт в ослабленном
        # режиме (AI-SBX-12); dsh и aider остаются в полной изоляции.
        # Отдельные --app-path для ~/.claude не нужны: домашний каталог
        # открыт целиком, сессии и MCP и так на месте.
        sandbox_opts=(--home-rw)
        # Поведенческие флаги задаются здесь, а не в settings.json того
        # каталога: settings.json принадлежит самому приложению и
        # пользователю (включённые плагины, тема, effortLevel) — Nix его не
        # генерирует и не перезаписывает (DOT-3, ARCH-15).
        extra_env=(
          --env "DISABLE_TELEMETRY=1"
          --env "DISABLE_ERROR_REPORTING=1"
          --env "DISABLE_AUTOUPDATER=1"
        )
        # R8.7 (AI-CTX-3): список MCP-серверов подсистемы — из dotfiles/ai/
        # (сгенерированный файл, ссылка ~/.config/ai). Добавляется к MCP
        # пользователя, без --strict-mcp-config: свои серверы из ~/.claude.json
        # остаются. Определения MCP из проекта по-прежнему недоверенные
        # (AI-SBX-9) — решает само приложение. Путь виден внутри песочницы,
        # потому что роль идёт с открытым $HOME (--home-rw выше).
        if [ -r "$HOME/.config/ai/generated/claude.mcp.json" ]; then
          extra_bin_args=(--mcp-config "$HOME/.config/ai/generated/claude.mcp.json")
        fi
        # Через шлюз эту роль НЕ направляем (AI-GW-11: режим входа по подписке
        # шлюз не обслуживает). ПРОВЕРЕНО живьём: ANTHROPIC_BASE_URL +
        # ANTHROPIC_AUTH_TOKEN перебивают вход claude.ai («connectors are
        # disabled because ANTHROPIC_API_KEY or another auth source is set»)
        # и уводят запросы на облачную роль шлюза — то есть на модель слабее
        # той, что даёт подписка. Поэтому роль ходит со своей авторизацией из
        # ~/.claude, а туннель ей обеспечивают переменные прокси (NET-10),
        # которые песочница пробрасывает. Если понадобится обратное
        # (лимиты и журналы шлюза вместо подписки) — вернуть здесь
        # ANTHROPIC_BASE_URL/ANTHROPIC_AUTH_TOKEN и ANTHROPIC_MODEL=роль.
        ;;
      dsh)
        bin=${lib.getExe deepseekHarness}
        # DSH_HOME — каталог СОСТОЯНИЯ, не конфига: dsh сам создаёт в нём
        # профиль из поставляемого шаблона и ставит туда бандлы (pnpm), то
        # есть каталог обязан быть записываемым. Поэтому он в state_dir, а
        # не в ~/.config (который песочница монтирует только на чтение) —
        # ПРОВЕРЕНО: с ~/.config dsh падает на создании профиля.
        extra_env=(--env "DSH_HOME=$state_dir/dsh-home")
        # dsh говорит с провайдером по протоколу Anthropic и берёт ключ из
        # DEEPSEEK_API_KEY. Направляем его в наш шлюз: облачная роль, лимиты
        # и журналы остаются на шлюзе (AI-GW-2/AI-GW-6), отдельный ключ
        # DeepSeek не нужен. Без ключа dsh падает с «MISSING_CREDENTIAL:
        # llm-deepseek» — ПРОВЕРЕНО живьём.
        #
        # Адрес и модель задаются ПАТЧЕМ ПРОФИЛЯ, а не переменными: адрес
        # DEEPSEEK_BASE_URL dsh читает, но имя модели берёт только из
        # конфигурации плагина `agent-default-model` (ПРОВЕРЕНО: с одним
        # DEEPSEEK_BASE_URL запрос доходит до шлюза, но тот отвечает «could
        # not auto resolve a provider» — dsh присылает своё `deepseek-flash`).
        # Патч кладётся в профиль внутри DSH_HOME (состояние, не dotfiles) при
        # каждом запуске: его содержимое выводится из политики хоста — имя
        # роли от Nix и адрес из машинного слоя, констант здесь нет
        # (AI-ROLE-2, DOT-1). `provider` остаётся штатным `deepseek-official`:
        # это внутреннее имя маршрута dsh, а не выбор провайдера — реальный
        # провайдер за ролью решает шлюз.
        if [ -n "''${AI_GATEWAY_URL:-}" ] && [ -n "$gw_key" ]; then
          export DEEPSEEK_API_KEY="$gw_key"
          sandbox_opts+=(--pass-env DEEPSEEK_API_KEY)
          # Патч пишется в оба поставляемых профиля, которые использует
          # лаунчер (web — полноценный агент, headless — одноразовая задача):
          # какой из них запустится, зависит от аргументов ниже. Каталог
          # создаём сами — на первом запуске его ещё нет, а dsh дописывает
          # остальное содержимое профиля рядом, не затирая патч (ПРОВЕРЕНО
          # на чистом DSH_HOME).
          for dsh_prof in web headless; do
            dsh_profile="$state_dir/dsh-home/profiles/$dsh_prof"
            mkdir -p "$dsh_profile"
            # Содержимое — из хранилища (патчи профилей фичи, там же
            # почему выключен встроенный поиск); подставляется только адрес.
            case "$dsh_prof" in
              web) dsh_src=${dshProfile.web} ;;
              *) dsh_src=${dshProfile.headless} ;;
            esac
            dsh_text=$(<"$dsh_src")
            printf '%s\n' "''${dsh_text//@GATEWAY_URL@/$AI_GATEWAY_URL}" > "$dsh_profile/cordis.patch.yml"
          done
        fi
        # all_proxy отдаём пустым: dsh не поддерживает SOCKS и предупреждает об
        # этом на каждом запуске; HTTPS всё равно идёт через https_proxy, так
        # что туннель не обходится (AI_SUBSYSTEM.md §2.6, NET-10).
        extra_env+=(
          --env "all_proxy="
          --env "ALL_PROXY="
        )
        # --profile обязателен. Поставляемые шаблоны (PROFILE_TEMPLATES в
        # dsh-app-boot): acp, web, headless, sdk, sdk-minimal. Терминального
        # интерфейса среди них НЕТ (`tui` из примеров --help — имя
        # пользовательского профиля, шаблона с таким именем нет; бандл
        # `experimental-terminal` — про живучесть shell-процессов, не UI).
        # Полноценный интерактивный агент у dsh — это профиль `web`: он
        # поднимает локальный сервер на loopback и печатает URL с токеном
        # (сессии, субагенты, план-режим — всё там). Поэтому:
        #   без аргументов            → web, полноценный агент;
        #   с текстом задачи          → headless, «выполнить и выйти»;
        #   с флагами (--*)           → как есть, профиль выбирает пользователь.
        # --no-open: браузер запускает человек снаружи, а не песочница —
        # внутри неё у браузера нет ни профиля, ни доступа к сессии
        # рабочего стола (AI-SBX-2). Порт на loopback доступен хосту, потому
        # что сетевое пространство имён общее (AI-SBX-5, ПРОВЕРИТЬ).
        case "''${1:-}" in
          --*) : ;; # явные флаги dsh — передаём как есть, профиль выбирает пользователь
          "") extra_bin_args=(--profile web --no-open) ;;
          *) extra_bin_args=(--profile headless) ;;
        esac
        ;;
      aider)
        bin=${lib.getExe aiderChat}
        # Конфиг читается из ~/.config/aider напрямую: каталог роли — в белом
        # списке песочницы (`--config`, только чтение), симлинк в dotfiles
        # разрешает ядро. Прежняя копия в state_dir была обходом старой схемы.
        sandbox_opts=(--config aider)
        extra_bin_args=(
          --config "$HOME/.config/aider/aider.conf.yml"
          --model "openai/${aiderRole}"
        )
        # Суффикс `/v1`: aider (через litellm) добавляет к базе
        # `/chat/completions`, а OpenAI-совместимый маршрут шлюза — под /v1
        # (ПРОВЕРЕНО живым запросом к /v1/chat/completions).
        [ -n "''${AI_GATEWAY_URL:-}" ] && extra_env+=(--env "OPENAI_API_BASE=$AI_GATEWAY_URL/v1")
        if [ -n "$gw_key" ]; then
          export OPENAI_API_KEY="$gw_key"
          sandbox_opts+=(--pass-env OPENAI_API_KEY)
        fi
        ;;
      *) usage ;;
    esac

    # AI-SBX-4: direnv активирует проектное окружение перед запуском
    # бинарника роли — обязательно ВНУТРИ песочницы (`agents-sandbox-exec`
    # первым аргументом после `--`), а не снаружи: `direnv exec`
    # полностью заменяет PATH на окружение project_dir, и если обернуть
    # этим саму agents-sandbox-exec, она перестаёт быть видна (PATH
    # заменён раньше, чем мы входим в песочницу — проверено живьём).
    # Без .envrc в project_dir — безвредный no-op.
    exec agents-sandbox-exec "$project_dir" "$state_dir" "$mode" \
      ''${extra_env[@]+"''${extra_env[@]}"} ''${sandbox_opts[@]+"''${sandbox_opts[@]}"} -- \
      direnv exec "$project_dir" "$bin" "''${extra_bin_args[@]}" "$@"
  '';
}
