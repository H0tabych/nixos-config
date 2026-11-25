# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Адаптер тяжёлого агента (AI-AGT-9, ADR-47): всё знание о Claude Code — здесь, лаунчер
# общий и про `claude` не знает. Адаптер — данные + фрагмент bash, который лаунчер вставляет
# в ветку `case`. Переменные лаунчера: `state_dir`, `agent_mode` (autonomous|controlled),
# массивы `extra_env`, `extra_bin_args`, `sandbox_opts`, `publish`; пакет — переменная `bin`.
#
# Claude работает так, как задумали разработчики (ADR-48, решение владельца 2026-11-14:
# «без лишних защит»): память, навыки, плагины, сессии, фоновые сессии и `claude agents`
# штатные, в настоящем ~/.claude (CLAUDE_CONFIG_DIR не подменяется: со свежим каталогом агент
# не видит своих MCP и сессий, ПРОВЕРЕНО). Граница — долгоживущая песочница (`longLived`,
# AI-SBX-13): одна на пользователя, весь $HOME на запись (ослабленный режим AI-SBX-12, решение
# пользователя 2026-10-29), сеть `online`. Политика уровня 0 — флагами и окружением запуска,
# файлы приложения Nix не пишет (DOT-3).
{ lib, claudeCode }:
{
  name = "claude";
  # Вход по подписке мимо шлюза (AI-GW-11): запросы модели шлюз не обслуживает, в `offline`
  # не запускается (облако недоступно, AI-SBX-5). Ключ шлюза (`claude-online`) нужен только
  # для инструментов MCP-шлюза (AI-GW-14, R9.23) — как у `dsh`, лаунчер читает его значением.
  cloudOnly = true;
  gatewayKey = true;

  longLived = {
    # `--device`: /dev/kvm и /dev/dri хоста (AI-SBX-14) — проверки переносимости в ВМ и живой Wayland.
    # `--wayland`: сокет Wayland-сессии и GL хоста (AI-SBX-15) — окно браузера Playwright.
    sandboxOpts = [
      "--home-rw"
      "--wayland"
      "--device"
      "kvm"
      "--device"
      "dri"
    ];
    # Реестр живых процессов Claude (`~/.claude/sessions/<pid>.json` и ключи
    # `<pid>.<хэш>.key`) помечает каждую запись доменом PID: машина + inode пространства PID.
    # Запись чужого домена Claude не может проверить и считает живой навсегда (2.1.323:
    # `isHeldInAnotherPidDomain`) — сессия «открыта в другом окне», вернуться в неё нельзя (D23).
    # Inode пространства PID новый у каждого запуска песочницы, а в момент её старта процессов
    # claude нет нигде: старая песочница при остановке убивает всё своё пространство PID. Поэтому
    # все записи на этот момент мертвы, и реестр очищается, как его очистил бы сам Claude.
    # Беседы (`projects/`), фоновые сессии (`jobs/`) и супервизор (`daemon*`) не трогаются.
    onStart = ''
      find "$HOME/.claude/sessions" -maxdepth 1 -type f \
        \( -name '[0-9]*.json' -o -name '[0-9]*.key' \) -delete 2> /dev/null || true
    '';
  };

  shell = ''
    bin=${lib.getExe claudeCode}
    # Телеметрия и автообновление выключены: обновляет только Nix (ARCH-14).
    extra_env=(
      --env "DISABLE_TELEMETRY=1"
      --env "DISABLE_ERROR_REPORTING=1"
      --env "DISABLE_AUTOUPDATER=1"
    )
    # Известные файлы агента в проекте (AI-AGT-9): отчёт лаунчера помечает их «файл агента».
    project_files=$'.claude/settings.local.json|личные настройки Claude Code (держите в .gitignore)\nCLAUDE.local.md|личные инструкции Claude Code (держите в .gitignore)'
    # Список MCP подсистемы (AI-CTX-3) — плагин `ai-tools` из dotfiles в штатной конфигурации
    # Claude (REGISTRY.md, запись `ai`), а не флаг запуска: флаги окна не восстанавливаются при
    # `--resume` и в фоновых сессиях (ADR-48). Без --strict-mcp-config: строгий режим отключил
    # бы плагины и подключения аккаунта (ADR-47); MCP из проекта по-прежнему подтверждает
    # человек (AI-SBX-9) — решает само приложение. Плагин берёт адрес и ключ входа MCP-шлюза из
    # окружения (AI_MCP_URL, AI_MCP_KEY): ключ — значением, не в argv и не в файле.
    # Имя переменной не «учётное» для Claude Code (такие читаются пустыми в url/headers).
    if [ -n "''${AI_GATEWAY_URL:-}" ] && [ -n "$gw_key" ]; then
      export AI_MCP_KEY="$gw_key"
      sandbox_opts+=(--pass-env AI_MCP_KEY)
      extra_env+=(--env "AI_MCP_URL=$AI_GATEWAY_URL/mcp")
    fi
    # Режимы (AI-AGT-1): `autonomous` — как задумано разработчиками (разрешения из
    # настроек пользователя в ~/.claude, флага нет); `controlled` — подтверждение каждой
    # правки и команды (`--permission-mode manual`).
    if [ "$agent_mode" = controlled ]; then
      tail_args+=(--permission-mode manual)
    fi
    # Через шлюз не направляем (AI-GW-11): ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN
    # перебили бы вход claude.ai и увели запросы на более слабую роль (ПРОВЕРЕНО).
    # Выход — сокетами хоста (AI-SBX-5).
  '';
}
