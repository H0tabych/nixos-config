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
  dshRole,
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

    # Ключ доступа к шлюзу — только в переменную окружения процесса
    # (см. комментарий к фиче выше), никогда в файл/лог.
    gw_key=""
    if [ -n "''${AI_GATEWAY_ACCESS_KEY_FILE:-}" ] && [ -r "$AI_GATEWAY_ACCESS_KEY_FILE" ]; then
      gw_key=$(cat "$AI_GATEWAY_ACCESS_KEY_FILE")
    fi

    # extra_env — путь к конфигу роли из dotfiles (AI-AGT-3) и адрес/ключ
    # шлюза под именами переменных, которые понимает конкретное
    # приложение; доплата к белому списку agents-sandbox-exec (--env,
    # AI-SBX-3). extra_bin_args — то же самое, но там, где приложение
    # берёт значение только аргументом командной строки (aider). $HOME
    # здесь — настоящий домашний каталог: agent-launcher выполняется до
    # входа в песочницу.
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
          extra_env+=(--env "DEEPSEEK_API_KEY=$gw_key")
          # Патч пишется в оба поставляемых профиля, которые использует
          # лаунчер (web — полноценный агент, headless — одноразовая задача):
          # какой из них запустится, зависит от аргументов ниже. Каталог
          # создаём сами — на первом запуске его ещё нет, а dsh дописывает
          # остальное содержимое профиля рядом, не затирая патч (ПРОВЕРЕНО
          # на чистом DSH_HOME).
          for dsh_prof in web headless; do
            dsh_profile="$state_dir/dsh-home/profiles/$dsh_prof"
            mkdir -p "$dsh_profile"
            # printf, а не heredoc: отступы внутри строки Nix правит
            # форматировщик, и терминатор heredoc уезжает от начала строки
            # (ПРОВЕРЕНО: скрипт ломался после nix fmt).
            {
              printf '%s\n' "# Сгенерировано agent-launcher (R8.6) — правки будут перезаписаны."
              printf '%s\n' "- id: llm-deepseek"
              printf '%s\n' "  config:"
              printf '%s\n' "    baseURL: $AI_GATEWAY_URL/anthropic"
              printf '%s\n' "- id: agent-default-model"
              printf '%s\n' "  config:"
              printf '%s\n' "    provider: deepseek-official"
              printf '%s\n' "    model: ${dshRole}"
            } > "$dsh_profile/cordis.patch.yml"
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
        # Конфиг тоже засеивается копией в state_dir, как у claude, и по той
        # же причине «путь снаружи ≠ путь внутри»: ~/.config/<app> — симлинк
        # в рабочую копию dotfiles, которая лежит под $HOME, а $HOME внутри
        # песочницы подменён на tmpfs — цель симлинка недостижима, хотя сам
        # симлink виден (ПРОВЕРЕНО живьём: "Unable to open config file").
        # Копия снимает это, не открывая песочнице ещё один путь хоста.
        aider_conf="$state_dir/aider.conf.yml"
        mkdir -p "$state_dir"
        if [ -r "$HOME/.config/aider/aider.conf.yml" ]; then
          install -m600 "$HOME/.config/aider/aider.conf.yml" "$aider_conf"
        fi
        extra_bin_args=(
          --config "$aider_conf"
          --model "openai/${aiderRole}"
        )
        # Суффикс `/v1`: aider (через litellm) добавляет к базе
        # `/chat/completions`, а OpenAI-совместимый маршрут шлюза — под /v1
        # (ПРОВЕРЕНО живым запросом к /v1/chat/completions).
        [ -n "''${AI_GATEWAY_URL:-}" ] && extra_env+=(--env "OPENAI_API_BASE=$AI_GATEWAY_URL/v1")
        [ -n "$gw_key" ] && extra_env+=(--env "OPENAI_API_KEY=$gw_key")
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
