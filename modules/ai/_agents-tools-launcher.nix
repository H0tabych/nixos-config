# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Лаунчер агентов (AI-AGT-4: единственный способ запуска). Отделён от фичи по границе
# контракта (STR-5). Лаунчер общий и конкретных агентов не знает (AI-AGT-9): всё про
# агента — в адаптере (`adapters`, _agents-tools-<агент>.nix): имя, признак подписки,
# нужен ли ключ шлюза и фрагмент bash, который заполняет `bin`, `extra_env`,
# `extra_bin_args` (перед аргументами пользователя), `tail_args` (после них), `sandbox_opts`, `publish`. Песочницу даёт владелец (`sandboxExec`).
{
  pkgs,
  lib,
  sandboxExec,
  netTool,
  gitTool,
  adapters,
}:
let
  names = a: lib.concatStringsSep " " (map (x: x.name) a);
  allNames = names adapters;
  usageList = lib.concatStringsSep "|" (map (a: a.name) adapters);
  subscriptionNames = names (lib.filter (a: a.subscription) adapters);
  gatewayNames = names (lib.filter (a: a.gatewayKey) adapters);
  agentCases = lib.concatMapStrings (a: ''
    ${a.name})
    ${a.shell}
        ;;
  '') adapters;
in
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
    # Составы из адаптеров (AI-AGT-9), с пробелами по краям — для поиска по `*" имя "*`.
    all_agents=" ${allNames} "
    subscription_agents=" ${subscriptionNames} "
    gateway_agents=" ${gatewayNames} "

    usage() {
      echo "usage: agent-launcher <${usageList}> [--controlled] [--offline] [-- args...]" >&2
      exit 1
    }
    [ "$#" -ge 1 ] || usage
    role=$1
    shift

    case "$all_agents" in
      *" $role "*) ;;
      *) usage ;;
    esac

    # Сеть (AI-SBX-5, AI-SEC-6): облако по умолчанию разрешено (`online`); `offline` — под
    # корнем `cloud = "deny"` из ~/.config/ai/roots.toml (владелец) либо флагом на этот
    # запуск. Проект режим не меняет (AI-SEC-5).
    # Режим работы агента (AI-AGT-1): `autonomous` по умолчанию; `--controlled` — показ
    # изменений и подтверждение правок и команд (как — решает адаптер).
    mode=""
    agent_mode=autonomous
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --offline) mode=offline ;;
        --controlled) agent_mode=controlled ;;
        --online)
          echo "agent-launcher: флага --online больше нет: облако по умолчанию разрешено (ADR-47)" >&2
          exit 1
          ;;
        --)
          shift
          break
          ;;
        *) break ;;
      esac
      shift
    done
    # AI-SBX-7 (ADR-44): работа на месте. Каталог проекта — корень git-дерева
    # (иначе текущий), на запись; метаданные git в песочнице ro (agents-sandbox-exec).
    project_dir=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")
    [ -n "$mode" ] || mode=$(agents-net mode "$project_dir")
    echo "agent-launcher: сеть $mode, режим $agent_mode" >&2
    case "$subscription_agents" in
      *" $role "*)
        if [ "$mode" = offline ]; then
          echo "agent-launcher: $role работает по подписке и в offline не запускается (AI-SBX-5)" >&2
          exit 1
        fi
        ;;
    esac

    # Адрес шлюза и путь к ключу — из машинного слоя (DOT-5, AI-CMP-4), а не
    # из того, что досталось интерактивной сессии: файл пишет фича
    # llm-gateway, но `.zshrc` его не подключает (ПРОВЕРЕНО: AI_GATEWAY_URL в
    # сессии пуст, из-за чего агенты уходили мимо шлюза). Берём сами, не
    # перекрывая уже заданное в окружении.
    if [ -z "''${AI_GATEWAY_URL:-}" ] && [ -r "$HOME/.config/machine.d/ai-gateway-env" ]; then
      # shellcheck source=/dev/null  # файл машинного слоя, вне сборки
      . "$HOME/.config/machine.d/ai-gateway-env"
    fi

    # Ключ доступа к шлюзу (AI-SBX-3, ADR-45): свой файл `<агент>-<режим сети>` в каталоге
    # ключей службы. Читается здесь, снаружи песочницы, и уходит ТОЛЬКО значением в
    # окружение агента (`--pass-env`), никогда в файл/лог/argv. Агент без ключа (по
    # подписке, AI-GW-11) или без шлюза (AI-GW-9) авторизации не получает.
    gw_key=""
    case "$gateway_agents" in
      *" $role "*)
        if [ -n "''${AI_GATEWAY_KEYS_DIR:-}" ] && [ -r "$AI_GATEWAY_KEYS_DIR/$role-$mode" ]; then
          gw_key=$(cat "$AI_GATEWAY_KEYS_DIR/$role-$mode")
        fi
        ;;
    esac
    unset AI_GATEWAY_KEYS_DIR

    # Заполняет адаптер (AI-AGT-9): `bin` — бинарник; `extra_env` — доплата к белому списку
    # agents-sandbox-exec (--env, AI-SBX-3); `extra_bin_args` — аргументы агента (там, где
    # значение берётся только из командной строки); `sandbox_opts` — опции песочницы
    # (--home-rw, --config, --pass-env); `publish` — порты веб-интерфейса, публикуемые на
    # 127.0.0.1 хоста. $HOME здесь — настоящий домашний каталог: лаунчер выполняется до
    # входа в песочницу.
    state_dir="$HOME/.local/state/agents/$role"
    # Порт шлюза (на loopback хоста) — единственное, что offline пробрасывает наружу;
    # агентам по подписке шлюз не нужен.
    gw_port=""
    case "$gateway_agents" in
      *" $role "*)
        if [ -n "''${AI_GATEWAY_URL:-}" ]; then
          gw_port=''${AI_GATEWAY_URL##*:}
          gw_port=''${gw_port%%/*}
        fi
        ;;
    esac
    publish=()
    extra_env=()
    extra_bin_args=()
    tail_args=()
    sandbox_opts=()
    bin=""
    case "$role" in
    ${agentCases}      *) usage ;;
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

    # `agents-net run` поднимает пространство сети агента (pasta), охранник грузит правила
    # nftables до старта песочницы; не поднялось — агент не стартует (AI-SBX-6).
    rc=0
    agents-net run "$mode" "''${gw_port:--}" ''${publish[@]+"''${publish[@]}"} -- \
      agents-sandbox-exec "$project_dir" "$state_dir" "$mode" --cwd "$PWD" \
      ''${extra_env[@]+"''${extra_env[@]}"} ''${sandbox_opts[@]+"''${sandbox_opts[@]}"} -- \
      direnv exec "$project_dir" "$bin" "''${extra_bin_args[@]}" "$@" \
      ''${tail_args[@]+"''${tail_args[@]}"} || rc=$?

    agents-git report "$project_dir" "$report_snap" || true
    exit "$rc"
  '';
}
