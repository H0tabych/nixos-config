# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Лаунчер агентов (AI-AGT-4: единственный способ запуска). Отделён от фичи по границе
# контракта (STR-5). Лаунчер общий и конкретных агентов не знает (AI-AGT-9): всё про
# агента — в адаптере (`adapters`, _agents-tools-<агент>.nix): имя, признак подписки,
# нужен ли ключ шлюза и фрагмент bash, который заполняет `bin`, `extra_env`,
# `extra_bin_args` (перед аргументами пользователя), `tail_args` (после них), `sandbox_opts`, `publish`. Песочницу даёт владелец (`sandboxExec`).
# Адаптер с `longLived` (AI-SBX-13, ADR-48) работает в долгоживущей песочнице: лаунчер её
# поднимает (`agents-host ensure`) и входит (`agents-host enter`) — только `online` и только
# проект внутри $HOME (кроме $HOME в ней ничего нет).
{
  pkgs,
  lib,
  sandboxExec,
  netTool,
  gitTool,
  hostTool,
  adapters,
}:
let
  names = a: lib.concatStringsSep " " (map (x: x.name) a);
  allNames = names adapters;
  usageList = lib.concatStringsSep "|" (map (a: a.name) adapters);
  subscriptionNames = names (lib.filter (a: a.subscription) adapters);
  gatewayNames = names (lib.filter (a: a.gatewayKey) adapters);
  longLivedNames = names (lib.filter (a: a ? longLived) adapters);
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
    hostTool
    pkgs.git
  ];
  text = ''
    # Составы из адаптеров (AI-AGT-9), с пробелами по краям — для поиска по `*" имя "*`.
    all_agents=" ${allNames} "
    subscription_agents=" ${subscriptionNames} "
    gateway_agents=" ${gatewayNames} "
    longlived_agents=" ${longLivedNames} "

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
    longlived=0
    case "$longlived_agents" in
      *" $role "*)
        longlived=1
        if [ "$mode" = offline ]; then
          echo "agent-launcher: $role живёт в долгоживущей песочнице, она только online (AI-SBX-13)" >&2
          exit 1
        fi
        case "$(realpath -- "$project_dir")" in
          "$(realpath -- "$HOME")"/*) ;;
          *)
            echo "agent-launcher: $role работает только с проектами внутри домашнего каталога (AI-SBX-13)" >&2
            exit 1
            ;;
        esac
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
    # Долгоживущая песочница поднимается до снимка: её отказ — отказ запуска (AI-SBX-6).
    [ "$longlived" -eq 0 ] || agents-host ensure "$role"
    agents-git snapshot "$project_dir" "$report_snap" || true

    rc=0
    if [ "$longlived" -eq 1 ]; then
      # Вход в долгоживущую песочницу (AI-SBX-13): окружение AI-SBX-3 — потоком на fd 3.
      agents-host enter "$role" "$PWD" -- \
        direnv exec "$project_dir" "$bin" "''${extra_bin_args[@]}" "$@" \
        ''${tail_args[@]+"''${tail_args[@]}"} \
        3< <(agents-sandbox-exec - "$state_dir" online \
          ''${extra_env[@]+"''${extra_env[@]}"} ''${sandbox_opts[@]+"''${sandbox_opts[@]}"} --print-env) ||
        rc=$?
    else
      # `agents-net run` поднимает пространство сети агента (pasta), охранник грузит правила
      # nftables до старта песочницы; не поднялось — агент не стартует (AI-SBX-6).
      agents-net run "$mode" "''${gw_port:--}" ''${publish[@]+"''${publish[@]}"} -- \
        agents-sandbox-exec "$project_dir" "$state_dir" "$mode" --cwd "$PWD" \
        ''${extra_env[@]+"''${extra_env[@]}"} ''${sandbox_opts[@]+"''${sandbox_opts[@]}"} -- \
        direnv exec "$project_dir" "$bin" "''${extra_bin_args[@]}" "$@" \
        ''${tail_args[@]+"''${tail_args[@]}"} || rc=$?
    fi

    agents-git report "$project_dir" "$report_snap" || true
    exit "$rc"
  '';
}
