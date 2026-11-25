# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Адаптер подписочного агента второго вендора — OpenAI Codex CLI (AI-AGT-9, ADR-047…052).
# Контракт фрагмента `shell` — как у адаптера claude: переменные `state_dir`, `agent_mode`,
# массивы `extra_env`, `extra_bin_args`, `sandbox_opts`, `publish`; пакет — `bin`.
#
# Вход по подписке ChatGPT мимо шлюза (AI-GW-11, как у claude). Ключ шлюза нужен только для
# инструментов MCP-шлюза (AI-GW-14): `codex-online` из `my.ai.gateway.agents.codex.mcp`.
#
# Домашний каталог: CODEX_HOME = ~/.codex, а песочница AI-SBX-2 делает $HOME пустым — поэтому
# ослабленный режим AI-SBX-12 (`--home-rw`, решение владельца по образцу claude, ADR-48).
# Точечная альтернатива (цена — каталог создать руками до первого запуска):
#   `--app-path $HOME/.codex` и `extra_env=(--env "CODEX_HOME=$HOME/.codex")`.
#
# Режимы (AI-AGT-1): политика — не флагами, а `config.toml` кодекса; файлы приложения Nix не
# пишет (DOT-3), поэтому значения передаются опциями командной строки (`-c key=value`):
#   autonomous → approval_policy="on-request", sandbox_mode="danger-full-access"
#                (границу даёт песочница лаунчера, AI-SBX-8);
#   controlled → approval_policy="on-request", sandbox_mode="workspace-write".
# `codex exec` всегда использует `approval_policy=never` (по исходнику), поэтому задаём явно.
#
# MCP: HTTP-вход шлюза `$AI_GATEWAY_URL/mcp`; ключ — значением в окружении через
# `bearer_token_env_var = "AI_MCP_KEY"` (тот же ключ `online`, что у claude/dsh), в argv и в
# файле ключ не появляется (AI-SBX-3). Серверs проекта подключаются только с подтверждением
# (AI-SBX-9): строгий режим «только этот список» не включаем.
#
# Вход в подписку — интерактивно ОДИН раз: `codex login` (callback на 127.0.0.1:1455, браузер —
# хоста; лаунчер публикует порт так же, как для `dsh`). Дальше — только через лаунчер.
{ lib, codexCode }:
{
  name = "codex";
  subscription = true; # по подписке, мимо шлюза (AI-GW-11); в offline не запускается (AI-SBX-5)
  gatewayKey = true; # ключ `codex-online` — только для MCP-инструментов

  shell = ''
    bin=${lib.getExe codexCode}
    # AI-SBX-12: CODEX_HOME = $HOME/.codex, песочница не делает $HOME пустым.
    sandbox_opts+=(--home-rw)
    # Окно браузера Playwright на Wayland-сессии и GL хоста (AI-SBX-15, AI-SBX-14).
    sandbox_opts+=(--wayland --device dri)
    # Телеметрия/аналитика выключены (ARCH-14): обновляет только Nix.
    export DO_NOT_TRACK=1
    extra_env=(
      --env "DO_NOT_TRACK=1"
      --env "AI_MCP_URL=''${AI_GATEWAY_URL:-}/mcp"
    )
    # Ключ MCP-входа — значением в окружении, не в argv.
    if [ -n "''${AI_GATEWAY_URL:-}" ] && [ -n "$gw_key" ]; then
      export AI_MCP_KEY="$gw_key"
      sandbox_opts+=(--pass-env AI_MCP_KEY)
    fi
    project_files=$'.codex/|состояние и настройки Codex в проекте'
    # Настройки режима и MCP — опциями запуска (DOT-3: Nix не пишет config.toml).
    mode_args=()
    if [ "$agent_mode" = controlled ]; then
      mode_args=(-c 'approval_policy="on-request"' -c 'sandbox_mode="workspace-write"')
    else
      mode_args=(-c 'approval_policy="on-request"' -c 'sandbox_mode="danger-full-access"')
    fi
    mcp_args=()
    if [ -n "''${AI_MCP_URL:-}" ] && [ -n "''${AI_MCP_KEY:-}" ]; then
      mcp_args=(
        -c 'mcp_servers.gateway.url="'"$AI_MCP_URL"'"'
        -c 'mcp_servers.gateway.bearer_token_env_var="AI_MCP_KEY"'
      )
    fi
    extra_bin_args=( "''${mode_args[@]}" "''${mcp_args[@]}" )
  '';
}
