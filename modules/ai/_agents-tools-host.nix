# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Долгоживущая песочница агента (AI-SBX-13, ADR-48). Нужна агенту, у которого по замыслу
# разработчиков процессы живут дольше окна (у Claude — супервизор фоновых сессий, реестр
# живых процессов и `claude agents`): все его процессы обязаны жить в ОДНОМ пространстве PID,
# иначе записи соседних окон для него «чужие» и считаются живыми навсегда (D23). Поэтому
# песочница одна на пользователя и агента, а каждое окно входит в неё, а не строит свою.
# Механизм общий: что делать при старте и какие опции песочницы — в адаптере (`longLived`).
#
#   agents-host ensure <агент>   — поднять песочницу, если её нет: транзиентный юнит
#                                  `agents-<агент>.service` (живёт до выхода из сеанса или
#                                  `systemctl --user stop`; активация Home Manager его не трогает);
#   agents-host serve <агент>    — тело юнита: `onStart` адаптера, затем сеть `online` и песочница
#                                  без проекта (`agents-sandbox-exec -`), внутри — `sleep infinity`;
#   agents-host enter <агент> <каталог> -- <команда...>
#                                — войти и выполнить; окружение — NUL-поток на fd 3
#                                  (`agents-sandbox-exec --print-env`), не argv (ключи, AI-SBX-3).
#
# Вход в два шага — ограничение ядра (ПРОВЕРЕНО по исходникам setns, 2026-11-14): сетевое
# пространство принадлежит пространству пользователя pasta, остальные — вложенному пространству
# bwrap; из вложенного прав над родительским нет, а из начального setns(net) требует прав в нём.
# Первый `nsenter` входит в пространство пользователя и сеть pasta (через внешний процесс bwrap),
# второй — в пространства bwrap. Рабочий каталог задаёт `env -C` уже внутри: `nsenter --wd`
# открывает каталог в пространстве монтирования хоста и оставил бы процессу путь мимо корня.
# Ctrl+C в режиме без raw-терминала не должен убить ждущий `nsenter` раньше агента: сигналы
# INT/QUIT у цепочки игнорируются, а `env --default-signal` возвращает их агенту.
{
  pkgs,
  lib,
  netTool,
  sandboxExec,
  adapters,
}:
let
  longLived = lib.filter (a: a ? longLived) adapters;
  names = lib.concatMapStringsSep " " (a: a.name) longLived;
  serveCases = lib.concatMapStrings (a: ''
    ${a.name})
    ${a.longLived.onStart or ""}
        static_opts=(${lib.escapeShellArgs a.longLived.sandboxOpts})
        ;;
  '') longLived;
  nsenter = "${pkgs.util-linux}/bin/nsenter";
  env = "${pkgs.coreutils}/bin/env";
in
pkgs.writeShellApplication {
  name = "agents-host";
  runtimeInputs = [
    netTool
    sandboxExec
    pkgs.systemd
    pkgs.jq
    pkgs.coreutils
    pkgs.gawk
    pkgs.findutils
    pkgs.procps
  ];
  text = ''
    fail() {
      echo "agents-host: $*" >&2
      exit 1
    }
    usage() {
      echo "usage: agents-host <ensure|serve> <агент> | enter <агент> <каталог> -- <команда...>" >&2
      exit 1
    }
    [ "$#" -ge 2 ] || usage
    cmd=$1 agent=$2
    shift 2
    longlived_agents=" ${names} "
    case "$longlived_agents" in
      *" $agent "*) ;;
      *) fail "у агента «$agent» нет долгоживущей песочницы (AI-SBX-13)" ;;
    esac

    # Сеанс без XDG_RUNTIME_DIR (su, ssh) — менеджер пользователя всё равно на своём месте.
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    runtime="$XDG_RUNTIME_DIR/agents"
    info="$runtime/$agent.json"
    unit="agents-$agent"
    state_dir="$HOME/.local/state/agents/$agent"

    # pid (с хоста) процесса 1 песочницы. «child-pid» из сведений bwrap не годится: pasta
    # запускает команду в своём пространстве PID, и номер там другой (ПРОВЕРЕНО в ВМ: 26 против
    # 1905). Поэтому — по дереву юнита: pasta (главный процесс) → внешний bwrap → процесс 1;
    # совпадение пространства PID со сведениями bwrap отсекает чужой и переиспользованный pid.
    inner_pid() {
      local ns main outer pid
      [ -s "$info" ] || return 1
      ns=$(jq -r '."pid-namespace" // empty' "$info" 2> /dev/null) || return 1
      [ -n "$ns" ] || return 1
      main=$(systemctl --user show -p MainPID --value "$unit.service" 2> /dev/null) || return 1
      [ -n "$main" ] && [ "$main" != 0 ] || return 1
      for outer in $(pgrep -P "$main"); do
        for pid in $(pgrep -P "$outer"); do
          if [ "$(readlink "/proc/$pid/ns/pid" 2> /dev/null)" = "pid:[$ns]" ]; then
            echo "$pid"
            return 0
          fi
        done
      done
      return 1
    }

    case "$cmd" in
      serve)
        mkdir -p "$runtime" "$state_dir"
        rm -f "$info"
        static_opts=()
        case "$agent" in
        ${serveCases}      *) usage ;;
        esac
        exec agents-net run online - -- \
          agents-sandbox-exec - "$state_dir" online "''${static_opts[@]}" --info-file "$info" -- \
          ${pkgs.coreutils}/bin/sleep infinity
        ;;

      ensure)
        if ! systemctl --user is-active --quiet "$unit.service"; then
          systemctl --user reset-failed "$unit.service" > /dev/null 2>&1 || true
          rm -f "$info"
          # Одновременный старт из двух окон: второй systemd-run получает «unit exists» — это норма.
          # Без --collect: упавший юнит остаётся `failed` — ожидание ниже видит отказ сразу.
          systemd-run --user --quiet --unit="$unit" \
            --description="Долгоживущая песочница агента $agent (AI-SBX-13, ADR-48)" \
            -- "$(readlink -f "$0")" serve "$agent" ||
            systemctl --user is-active --quiet "$unit.service" ||
            fail "песочница не запущена: journalctl --user -u $unit"
        fi
        for _ in $(seq 1 150); do
          inner_pid > /dev/null && exit 0
          ! systemctl --user is-failed --quiet "$unit.service" || break
          sleep 0.1
        done
        {
          echo "agents-host: песочница «$agent» не поднялась (AI-SBX-6); журнал: journalctl --user -u $unit"
          systemctl --user status "$unit.service" --no-pager -n 15 2>&1 | sed 's/^/  /' || true
          [ ! -e "$info" ] || echo "  сведения bwrap: $(tr -d '\n' < "$info")"
        } >&2
        exit 1
        ;;

      enter)
        [ "$#" -ge 3 ] && [ "$2" = "--" ] || usage
        cwd=$1
        shift 2
        inner=$(inner_pid) || fail "песочница «$agent» не запущена (agents-host ensure $agent)"
        outer=$(awk '/^PPid:/ { print $2 }' "/proc/$inner/status")
        [ -n "$outer" ] || fail "нет внешнего процесса песочницы"
        mapfile -d "" -t kvs <&3
        exec 3<&-
        [ "''${#kvs[@]}" -gt 0 ] || fail "нет окружения входа (agents-sandbox-exec --print-env)"
        # Унаследованные дескрипторы внутрь не уходят: дескриптор каталога хоста открыл бы его
        # файловую систему мимо корня песочницы. 255 — сам скрипт (bash, закрывается при exec).
        for fd in /proc/self/fd/*; do
          fd=''${fd##*/}
          case "$fd" in 0 | 1 | 2 | 255) continue ;; esac
          eval "exec $fd>&-" 2> /dev/null || true
        done
        # Окружение — ровно перечень AI-SBX-3; дальше только абсолютные пути.
        # Имена — из `env -0`, а не `compgen -e`: у bash из writeShellApplication нет `compgen`
        # (без readline), и очистка молча не выполнялась (R9.24: окружение хоста попадало внутрь).
        mapfile -d "" -t inherited < <(${env} -0)
        for kv in "''${inherited[@]}"; do
          unset "''${kv%%=*}" 2> /dev/null || true
        done
        for kv in "''${kvs[@]}"; do
          export "''${kv?}"
        done
        trap "" INT QUIT
        exec ${nsenter} -t "$outer" -U -n --preserve-credentials -- \
          ${nsenter} -t "$inner" -U -m -p -i -u -C --preserve-credentials -- \
          ${env} -C "$cwd" --default-signal=INT,QUIT "$@"
        ;;

      *) usage ;;
    esac
  '';
}
