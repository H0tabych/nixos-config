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
  # Вход по подписке мимо шлюза (AI-GW-11): ключа шлюза нет, в `offline` не запускается
  # (облако недоступно, AI-SBX-5).
  subscription = true;
  gatewayKey = false;

  longLived = {
    sandboxOpts = [ "--home-rw" ];
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
    # Список MCP подсистемы (AI-CTX-3) — к MCP пользователя, без --strict-mcp-config:
    # строгий режим отключил бы плагины и подключения аккаунта (ADR-47). Определения MCP
    # из проекта по-прежнему подтверждаются человеком (AI-SBX-9) — решает само приложение.
    if [ -r "$HOME/.config/ai/generated/claude.mcp.json" ]; then
      # Флаги адаптера — ПОСЛЕ аргументов пользователя (`tail_args`): подкоманда
      # (`daemon`, `attach`, `agents`) распознаётся только первым словом, а флаг впереди
      # превращает её в текст задачи (ПРОВЕРЕНО на машине). Форма с `=`: `--mcp-config`
      # принимает несколько значений и без `=` съедает следующие аргументы как пути.
      tail_args+=("--mcp-config=$HOME/.config/ai/generated/claude.mcp.json")
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
