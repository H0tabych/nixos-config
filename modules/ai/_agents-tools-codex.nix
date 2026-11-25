# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Адаптер подписочного агента второго вендора — OpenAI Codex CLI (AI-AGT-1, AI-AGT-9, ADR-052).
# Контракт фрагмента `shell` — как у адаптера claude: переменные `state_dir`, `agent_mode`,
# `gw_key`, массивы `extra_env`, `extra_bin_args`, `sandbox_opts`, `publish`; пакет — `bin`.
#
# Модель — по подписке ChatGPT мимо шлюза и в родном протоколе агента (AI-GW-11, ADR-051): шлюз
# посредником не стоит. Ключ шлюза (`codex-online`) нужен только инструментам MCP-шлюза
# (AI-GW-14): права ему даёт `my.ai.gateway.agents.codex.mcp`.
#
# Домашний каталог: CODEX_HOME = ~/.codex, а песочница AI-SBX-2 делает $HOME пустым — поэтому
# ослабленный режим AI-SBX-12 (`--home-rw`, решение владельца по образцу claude). Точечная
# альтернатива (цена — каталог создать руками до первого запуска): `--app-path $HOME/.codex` и
# `extra_env=(--env "CODEX_HOME=$HOME/.codex")`.
#
# Политика уровня 0 — опциями запуска `-c ключ=значение` (значение — TOML), а не файлом: файлы
# приложения Nix не пишет (DOT-3), а `~/.codex/config.toml` ведёт сам Codex.
# Режимы (AI-AGT-1):
#   autonomous → approval_policy="on-request", sandbox_mode="danger-full-access"
#                (границу даёт песочница лаунчера, AI-SBX-8);
#   controlled → approval_policy="on-request", sandbox_mode="workspace-write".
#                ПРОВЕРИТЬ: собственная песочница Codex внутри песочницы лаунчера (вложенные
#                пространства имён); не заработает — `approval_policy="untrusted"` и
#                `sandbox_mode="read-only"`.
# `codex exec` всегда использует `approval_policy=never` (по исходнику), поэтому задаём явно.
# Телеметрия и проверка обновлений выключены (ARCH-14): обновляет только Nix. `DO_NOT_TRACK`
# Codex не читает (ПРОВЕРЕНО по бинарнику 0.166.0), поэтому — ключи конфигурации.
#
# MCP (AI-CTX-3): локальные серверы общего списка — строки `generated/codex/local.overrides`
# из dotfiles (генератор `ai/gen/gen.py`), вход MCP-шлюза — `$AI_GATEWAY_URL/mcp`; ключ уходит
# заголовком `x-bf-vk` из переменной окружения (`env_http_headers`), в argv и в файле его нет
# (AI-SBX-3). Серверы проекта подключаются только с подтверждением (AI-SBX-9): строгий режим
# «только этот список» не включаем.
#
# Вход в подписку — интерактивно ОДИН раз: `agent-launcher codex login --device-auth` (код
# вводится в браузере хоста; обратный вызов на 127.0.0.1:1455, которого вне песочницы не видно,
# не нужен). Дальше — только через лаунчер.
{ lib, codexCode }:
{
  name = "codex";
  cloudOnly = true; # по подписке, мимо шлюза (AI-GW-11); в offline не запускается (AI-SBX-5)
  gatewayKey = true; # ключ `codex-online` — только для MCP-инструментов (AI-GW-14)

  shell = ''
    bin=${lib.getExe codexCode}
    # AI-SBX-12: CODEX_HOME = $HOME/.codex, песочница не делает $HOME пустым.
    sandbox_opts+=(--home-rw)
    # Окно браузера Playwright на Wayland-сессии и GL хоста (AI-SBX-15, AI-SBX-14).
    sandbox_opts+=(--wayland --device dri)
    project_files=$'.codex/|состояние и настройки Codex в проекте'

    mode_args=(
      -c 'approval_policy="on-request"'
      -c 'analytics.enabled=false'
      -c 'check_for_update_on_startup=false'
    )
    if [ "$agent_mode" = controlled ]; then
      mode_args+=(-c 'sandbox_mode="workspace-write"')
    else
      mode_args+=(-c 'sandbox_mode="danger-full-access"')
    fi

    # Локальные серверы общего списка MCP (нет файла — без них).
    mcp_args=()
    mcp_file="$HOME/.config/ai/generated/codex/local.overrides"
    if [ -r "$mcp_file" ]; then
      while IFS= read -r line; do
        case "$line" in "" | "#"*) continue ;; esac
        mcp_args+=(-c "$line")
      done < "$mcp_file"
    fi
    # Вход MCP-шлюза — только когда есть шлюз и ключ (AI-GW-9): ключ значением в окружении.
    if [ -n "''${AI_GATEWAY_URL:-}" ] && [ -n "$gw_key" ]; then
      export AI_MCP_KEY="$gw_key"
      sandbox_opts+=(--pass-env AI_MCP_KEY)
      mcp_args+=(
        -c "mcp_servers.gateway.url=\"$AI_GATEWAY_URL/mcp\""
        -c 'mcp_servers.gateway.env_http_headers={x-bf-vk="AI_MCP_KEY"}'
      )
    fi
    extra_bin_args=("''${mode_args[@]}" "''${mcp_args[@]}")
  '';
}
