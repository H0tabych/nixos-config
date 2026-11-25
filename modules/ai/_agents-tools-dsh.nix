# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Адаптер альтернативного агента — DeepSeek Harness, `dsh` (AI-AGT-9, ADR-47, ADR-051).
# Контракт фрагмента `shell` — как у адаптера claude. Дополнительно лаунчер даёт
# `gw_key` (ключ шлюза значением, пусто — шлюза нет, AI-GW-9; нужен только инструментам MCP-шлюза)
# и `$AI_GATEWAY_URL`.
#
# Модель — напрямую у провайдера, в родном протоколе агента (ADR-051): dsh говорит на Anthropic
# Messages и ходит на `https://api.deepseek.com/anthropic` (`DEEPSEEK_BASE_URL` не задаём — это
# умолчание адаптера `llm-deepseek`). Посредник-шлюз стоял между ними преобразователем форматов
# (Messages → внутренняя схема → OpenAI chat-endpoint) и молча выключал рассуждение; убран.
# Ключ провайдера — файл из sops (фича `agents-keys`, путь в `AI_AGENT_KEYFILE_DSH`), лаунчер
# читает его снаружи песочницы и отдаёт значением в `DEEPSEEK_API_KEY` (AI-SBX-3). Модель и
# `reasoningEffort` выбирает владелец в интерфейсе dsh: хост за него не решает.
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
  # Ходит к модели только через облако: в `offline` не запускается (AI-SBX-5). Ключ шлюза —
  # только для инструментов MCP-шлюза (AI-GW-14), как у claude.
  cloudOnly = true;
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
    # Журналы локальных MCP-серверов (code-context-lsp) — в файл, а не в терминал: клиент dsh
    # отдаёт им свой stderr, и шум заглушает ссылку веб-интерфейса.
    extra_env+=(--env "CODE_CONTEXT_LSP_LOG=$state_dir/mcp-lsp.log")
    # Окно браузера Playwright на Wayland-сессии и GL хоста (AI-SBX-15, AI-SBX-14).
    sandbox_opts+=(--wayland --device dri)
    if [ "$agent_mode" = controlled ]; then
      extra_env+=(--env "DSH_PERMISSION_MODE=workspace-write")
    else
      extra_env+=(--env "DSH_PERMISSION_MODE=danger-full-access")
    fi
    # Подключение к провайдеру (ADR-051): ключ — значением из файла agents-keys; адрес —
    # умолчание dsh (`api.deepseek.com/anthropic`). Без ключа — отказ самого dsh
    # («MISSING_CREDENTIAL», ПРОВЕРЕНО), лаунчер предупреждает заранее.
    key_file=''${AI_AGENT_KEYFILE_DSH:-}
    if [ -n "$key_file" ] && [ -r "$key_file" ]; then
      DEEPSEEK_API_KEY=$(cat "$key_file")
      export DEEPSEEK_API_KEY
      sandbox_opts+=(--pass-env DEEPSEEK_API_KEY)
    else
      echo "agent-launcher: dsh: нет файла ключа провайдера (AI_AGENT_KEYFILE_DSH, фича agents-keys)" >&2
    fi
    # Вход MCP-шлюза (AI-GW-14, R9.23): ключ шлюза значением в окружении; права на инструменты —
    # у ключа `dsh-online` (`offline` инструментов не получает).
    if [ -n "''${AI_GATEWAY_URL:-}" ] && [ -n "$gw_key" ]; then
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
