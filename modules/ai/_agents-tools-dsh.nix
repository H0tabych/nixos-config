# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Адаптер альтернативного агента — DeepSeek Harness, `dsh` (AI-AGT-9, AI-ROLE-5, ADR-47).
# Контракт фрагмента `shell` — как у адаптера claude. Дополнительно лаунчер даёт
# `gw_key` (ключ шлюза значением, пусто — шлюза нет, AI-GW-9) и `$AI_GATEWAY_URL`.
#
# Режимы (AI-AGT-1) — штатная переменная `DSH_PERMISSION_MODE` (ПРОВЕРЕНО
# `dsh --dump-config`, 0.2.1-rc.3: она выбирает песочницу и политику одобрений профиля):
#   autonomous → danger-full-access: одобрения не запрашиваются, внутренняя песочница
#                dsh не нужна — границу даёт песочница лаунчера (AI-SBX-8);
#   controlled → workspace-write: песочница dsh и запрос одобрения правок и команд.
#                ПРОВЕРИТЬ на машине: вложенная песочница dsh внутри песочницы лаунчера.
{
  lib,
  deepseekHarness,
  dshPolicy,
  webPortBase,
}:
{
  name = "dsh";
  subscription = false;
  gatewayKey = true;

  shell = ''
    bin=${lib.getExe deepseekHarness}
    # DSH_HOME — каталог СОСТОЯНИЯ: dsh создаёт в нём профили, ставит бандлы и сам
    # сохраняет выбор модели интерфейса, поэтому он в state_dir, а не в ~/.config (ro).
    # Файлы профилей лаунчер НЕ пишет (D18).
    # Общий корень агентов (инструкции `AGENTS.md` и навыки `skills/`, AI-AGT-8): штатно dsh
    # читает `~/.agents`, но домашний каталог в песочнице скрыт, а `~/.config/ai` (ссылка на
    # dotfiles/ai) виден на чтение — указываем его переменной окружения `DSH_AGENTS_HOME`.
    extra_env=(--env "DSH_HOME=$state_dir/dsh-home" --env "DSH_AGENTS_HOME=$HOME/.config/ai")
    if [ "$agent_mode" = controlled ]; then
      extra_env+=(--env "DSH_PERMISSION_MODE=workspace-write")
    else
      extra_env+=(--env "DSH_PERMISSION_MODE=danger-full-access")
    fi
    # Нативное подключение (AI-ROLE-5, R9.18): шлюз — корень Messages-совместимого API
    # (`DEEPSEEK_BASE_URL`, dsh добавляет `/v1/messages`), ключ доступа — `DEEPSEEK_API_KEY`
    # значением. Модели — собственные модели провайдера из каталога интерфейса; шлюз
    # маршрутизирует их по `nativeModels`, не подменяя. Без ключа и без шлюза — отказ
    # самого dsh («MISSING_CREDENTIAL», ПРОВЕРЕНО).
    if [ -n "''${AI_GATEWAY_URL:-}" ] && [ -n "$gw_key" ]; then
      export DEEPSEEK_API_KEY="$gw_key"
      sandbox_opts+=(--pass-env DEEPSEEK_API_KEY)
      extra_env+=(--env "DEEPSEEK_BASE_URL=$AI_GATEWAY_URL/anthropic")
      # Вход MCP-шлюза (AI-GW-14, R9.23): тот же ключ доступа, значением в окружении; права на
      # инструменты — у ключа `dsh-online` (`offline` инструментов не получает).
      export AI_MCP_KEY="$gw_key"
      sandbox_opts+=(--pass-env AI_MCP_KEY)
      extra_env+=(--env "AI_MCP_URL=$AI_GATEWAY_URL/mcp")
    fi
    # Политика Nix (поиск, телеметрия, менеджер плагинов) — патч из хранилища, на каждый
    # запуск и при любых флагах пользователя; в профили ничего не пишется.
    dsh_policy_args=(--patch ${dshPolicy})
    # Общий список MCP (AI-CTX-3, плагин `dsh-mcp-client`): локальные серверы — всегда, вход
    # шлюза — только когда заданы адрес и ключ (патч читает их из process.env). Файлы
    # генерирует dotfiles/ai/gen/gen.py; нет файлов — без них.
    mcp_dir="$HOME/.config/ai/generated/dsh"
    [ ! -r "$mcp_dir/local.cordis.yml" ] || dsh_policy_args+=(--patch "$mcp_dir/local.cordis.yml")
    if [ -n "''${AI_MCP_KEY:-}" ] && [ -r "$mcp_dir/gateway.cordis.yml" ]; then
      dsh_policy_args+=(--patch "$mcp_dir/gateway.cordis.yml")
    fi
    # --profile обязателен; терминального интерфейса нет, полноценный агент — профиль `web`
    # (сервер на loopback, URL с токеном). Без аргументов → web; с текстом задачи →
    # headless («выполнить и выйти»); с флагами (--*) — как есть, профиль выбирает
    # пользователь. --no-open: браузер запускает человек снаружи (AI-SBX-2). --port
    # фиксирован (на пользователя) и публикуется на 127.0.0.1 хоста (AI-SBX-5).
    case "''${1:-}" in
      --*) extra_bin_args=("''${dsh_policy_args[@]}") ;;
      "")
        dsh_port=$(( ${toString webPortBase} + $(id -u) - 1000 ))
        extra_bin_args=(--profile web "''${dsh_policy_args[@]}" --no-open --port "$dsh_port")
        publish+=("$dsh_port")
        ;;
      *) extra_bin_args=(--profile headless "''${dsh_policy_args[@]}") ;;
    esac
  '';
}
