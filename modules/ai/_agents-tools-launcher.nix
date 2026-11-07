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
  netTool,
  tunnelHttpPort,
  dshWebPortBase,
  gitTool,
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
    netTool
    gitTool
    pkgs.git
  ];
  text = ''
    usage() {
      echo "usage: agent-launcher <claude|dsh|aider> [--online|--offline] [-- args...]" >&2
      exit 1
    }
    [ "$#" -ge 1 ] || usage
    role=$1
    shift

    # Режим (AI-SBX-5, AI-SEC-6): без флага — по корням рабочих деревьев и маркеру
    # `.ai/offline` (agents-net mode); облако в рабочем дереве — только флагом
    # `--online` на этот запуск (проект включить его не может, AI-SEC-5).
    mode=""
    case "''${1:-}" in
      --online | --offline)
        mode=''${1#--}
        shift
        ;;
    esac
    [ "''${1:-}" = "--" ] && shift
    # AI-SBX-7 (ADR-44): работа на месте. Каталог проекта — корень git-дерева
    # (иначе текущий), на запись; метаданные git в песочнице ro (agents-sandbox-exec).
    project_dir=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")
    [ -n "$mode" ] || mode=$(agents-net mode "$project_dir" "$HOME/.config/ai/work-roots")
    echo "agent-launcher: режим $mode" >&2
    if [ "$role" = claude ] && [ "$mode" = offline ]; then
      echo "agent-launcher: claude работает по подписке и в offline не запускается (AI-SBX-5); для облака — флаг --online" >&2
      exit 1
    fi

    # Адрес шлюза и путь к ключу — из машинного слоя (DOT-5, AI-CMP-4), а не
    # из того, что досталось интерактивной сессии: файл пишет фича
    # llm-gateway, но `.zshrc` его не подключает (ПРОВЕРЕНО: AI_GATEWAY_URL в
    # сессии пуст, из-за чего агенты уходили мимо шлюза). Берём сами, не
    # перекрывая уже заданное в окружении.
    if [ -z "''${AI_GATEWAY_URL:-}" ] && [ -r "$HOME/.config/machine.d/ai-gateway-env" ]; then
      # shellcheck source=/dev/null  # файл машинного слоя, вне сборки
      . "$HOME/.config/machine.d/ai-gateway-env"
    fi

    # Ключ доступа к шлюзу (AI-SBX-3, ADR-45): свой файл `<агент>-<режим>` в каталоге
    # ключей службы. Читается здесь, снаружи песочницы, и уходит ТОЛЬКО значением в
    # окружение агента (`--pass-env`), никогда в файл/лог/argv. Агент без ключа
    # (claude — по подписке, AI-GW-11) или без шлюза (AI-GW-9) авторизации не получает.
    gw_key=""
    case "$role" in
      dsh|aider)
        if [ -n "''${AI_GATEWAY_KEYS_DIR:-}" ] && [ -r "$AI_GATEWAY_KEYS_DIR/$role-$mode" ]; then
          gw_key=$(cat "$AI_GATEWAY_KEYS_DIR/$role-$mode")
        fi
        ;;
    esac
    unset AI_GATEWAY_KEYS_DIR

    # extra_env — доплата к белому списку agents-sandbox-exec (--env,
    # AI-SBX-3): пути и адреса под именами, которые понимает приложение.
    # Ключ шлюза идёт отдельно, через export + `--pass-env` (см. ниже).
    # extra_bin_args — то же там, где приложение берёт значение только
    # аргументом командной строки. $HOME здесь — настоящий домашний каталог:
    # agent-launcher выполняется до входа в песочницу.
    state_dir="$HOME/.local/state/agents/$role"
    # Мосты в netns (agents-net): шлюз — всем, кроме claude (подписка, AI-GW-11);
    # HTTP-вход туннеля — только в online. Порт шлюза — из машинного слоя.
    net_specs=()
    if [ "$role" != claude ] && [ -n "''${AI_GATEWAY_URL:-}" ]; then
      gw_port=''${AI_GATEWAY_URL##*:}
      net_specs+=("fwd:gateway:''${gw_port%%/*}")
    fi
    tunnel_http_port="${if tunnelHttpPort == null then "" else toString tunnelHttpPort}"
    if [ "$mode" = online ] && [ -n "$tunnel_http_port" ]; then
      net_specs+=("fwd:proxy:$tunnel_http_port")
    fi

    extra_env=()
    extra_bin_args=()
    sandbox_opts=()
    # Каталоги роли в ~/.config (белый список AI-SBX-2, только чтение).
    case "$role" in
      claude)
        bin=${lib.getExe claudeCode}
        # CLAUDE_CONFIG_DIR НЕ подменяем: каталог ~/.claude — «каталог приложения»
        # (AI_SUBSYSTEM.md §2.5, класс D: настройки, MCP, плагины, сессии, вход);
        # со свежим каталогом агент не видит своих MCP и сессий (ПРОВЕРЕНО).
        # Решение пользователя (2026-10-29): тяжёлой роли — доступ ко всему $HOME на
        # запись (кросс-проектные правки), то есть ослабленный режим (AI-SBX-12);
        # dsh и aider — в полной изоляции. --app-path для ~/.claude не нужен.
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
        # Через шлюз эту роль НЕ направляем (AI-GW-11: вход по подписке шлюз не
        # обслуживает). ПРОВЕРЕНО: ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN
        # перебивают вход claude.ai и уводят запросы на более слабую роль шлюза.
        # Роль ходит со своей авторизацией из ~/.claude, выход — через мост
        # `proxy` в online (переменные прокси задаёт песочница, AI-SBX-5).
        ;;
      dsh)
        bin=${lib.getExe deepseekHarness}
        # DSH_HOME — каталог СОСТОЯНИЯ: dsh создаёт в нём профиль и ставит бандлы,
        # поэтому он в state_dir, а не в ~/.config (ro) — ПРОВЕРЕНО.
        extra_env=(--env "DSH_HOME=$state_dir/dsh-home")
        # dsh берёт ключ из DEEPSEEK_API_KEY — туда ключ доступа к шлюзу: роль,
        # лимиты и журналы остаются на шлюзе (AI-GW-2/AI-GW-6). Без ключа —
        # «MISSING_CREDENTIAL: llm-deepseek» (ПРОВЕРЕНО).
        # Адрес и модель — ПАТЧЕМ ПРОФИЛЯ: имя модели dsh берёт только из плагина
        # `agent-default-model` (ПРОВЕРЕНО: иначе шлюз отвечает «could not auto
        # resolve a provider»). Патч пишется в DSH_HOME при каждом запуске; имя
        # роли — от Nix, адрес — из машинного слоя (AI-ROLE-2, DOT-1). `provider:
        # deepseek-official` — внутреннее имя маршрута dsh, провайдера решает шлюз.
        if [ -n "''${AI_GATEWAY_URL:-}" ] && [ -n "$gw_key" ]; then
          export DEEPSEEK_API_KEY="$gw_key"
          sandbox_opts+=(--pass-env DEEPSEEK_API_KEY)
          # Патч — в оба профиля лаунчера (web, headless); каталог создаём сами,
          # dsh дописывает остальное рядом, не затирая патч (ПРОВЕРЕНО).
          for dsh_prof in web headless; do
            dsh_profile="$state_dir/dsh-home/profiles/$dsh_prof"
            mkdir -p "$dsh_profile"
            # Содержимое — из хранилища; подставляется только адрес.
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
        # --profile обязателен; шаблоны: acp, web, headless, sdk, sdk-minimal.
        # Терминального интерфейса нет; полноценный агент — профиль `web` (сервер
        # на loopback, URL с токеном). Поэтому:
        #   без аргументов            → web, полноценный агент;
        #   с текстом задачи          → headless, «выполнить и выйти»;
        #   с флагами (--*)           → как есть, профиль выбирает пользователь.
        # --no-open: браузер запускает человек снаружи, не песочница (AI-SBX-2).
        # --port фиксирован (на пользователя): веб-интерфейс внутри netns виден
        # хосту через обратный мост rev:dsh-web (AI-SBX-5), порт тот же.
        case "''${1:-}" in
          --*) : ;; # явные флаги dsh — передаём как есть, профиль выбирает пользователь
          "")
            dsh_port=$(( ${toString dshWebPortBase} + $(id -u) - 1000 ))
            extra_bin_args=(--profile web --no-open --port "$dsh_port")
            net_specs+=("rev:dsh-web:$dsh_port")
            ;;
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
    # Отчёт после сессии (AI-SBX-7): снимок ссылок, флагов индекса, вложенных
    # репозиториев и игнорируемых файлов до и сравнение после. Код возврата
    # агента сохраняется; отчёт печатается и при прерывании (Ctrl-C приходит и
    # агенту, и лаунчеру, который после этого доходит до отчёта).
    report_snap=$(mktemp)
    trap 'rm -f "$report_snap"' EXIT
    agents-git snapshot "$project_dir" "$report_snap" || true

    # `agents-net host` поднимает мосты на стороне хоста, снимает их при выходе и
    # отдаёт каталог сокетов песочнице через $AGENTS_NET_DIR; не поднялись — агент
    # не стартует (AI-SBX-6).
    for b in ''${net_specs[@]+"''${net_specs[@]}"}; do sandbox_opts+=(--bridge "$b"); done
    rc=0
    agents-net host ''${net_specs[@]+"''${net_specs[@]}"} -- \
      agents-sandbox-exec "$project_dir" "$state_dir" "$mode" --cwd "$PWD" \
      ''${extra_env[@]+"''${extra_env[@]}"} ''${sandbox_opts[@]+"''${sandbox_opts[@]}"} -- \
      direnv exec "$project_dir" "$bin" "''${extra_bin_args[@]}" "$@" || rc=$?

    agents-git report "$project_dir" "$report_snap" || true
    exit "$rc"
  '';
}
