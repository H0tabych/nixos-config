# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Сеть агентов (AI-SBX-5, ADR-44, R9.17): режим запуска и мосты между хостом и
# сетевым пространством имён песочницы. Единая точка истины для лаунчера
# (agents-tools.nix) и теста (tests/agent-network.nix) — проверяется ровно этот код.
#
# Внутри песочницы свой пустой netns (только `lo`): ни портов хоста, ни абстрактных
# сокетов. Наружу ведут только мосты `socat` через unix-сокеты, перечисленные
# явно; спецификация моста — `fwd:<имя>:<порт>` (внутри слушает 127.0.0.1:<порт>,
# снаружи соединение идёт на 127.0.0.1:<порт> хоста) или `rev:<имя>:<порт>` (наоборот:
# веб-интерфейс агента внутри, слушатель на хосте). Порты внутри и снаружи
# одинаковы, поэтому адреса шлюза и прокси из окружения остаются верными.
#
#   agents-net mode <проект> <файл корней>   → online | offline
#   agents-net host <спец>... -- <команда>   → мосты на стороне хоста, затем команда
#   agents-net inside <спец>... -- <команда> → мосты внутри песочницы, затем exec
#
# Fail-closed (AI-SBX-6): мост не поднялся за 5 секунд — команда не запускается.
{ pkgs }:
pkgs.writeShellApplication {
  name = "agents-net";
  runtimeInputs = [
    pkgs.socat
    pkgs.util-linux
    pkgs.coreutils
    pkgs.gnugrep
  ];
  text = ''
    bridge_root=/run/agents-bridge

    fail() {
      echo "agents-net: $*" >&2
      exit 1
    }

    # Слушатель TCP на loopback виден в /proc/net/tcp (состояние 0A) — проверка
    # без побочных соединений с мостом.
    listening() {
      grep -qi ":$(printf '%04X' "$1") 00000000:0000 0A" /proc/net/tcp
    }

    wait_for() {
      local i
      for i in $(seq 1 50); do
        "$@" && return 0
        sleep 0.1
      done
      return 1
    }

    # Мост поднялся, если условие выполнено И сам процесс жив: порт мог быть уже
    # занят чужим слушателем (bind не удался, а /proc/net/tcp «слушает»).
    wait_bridge() {
      local pid=$1
      shift
      wait_for "$@" || return 1
      sleep 0.2
      kill -0 "$pid" 2>/dev/null
    }

    # Разбор спецификаций до `--`; результат — массивы kinds/names/ports, остаток
    # аргументов (команда) — в rest.
    parse() {
      kinds=()
      names=()
      ports=()
      while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
        [[ "$1" =~ ^(fwd|rev):([a-z0-9-]+):([0-9]+)$ ]] || fail "неверная спецификация моста: $1"
        kinds+=("''${BASH_REMATCH[1]}")
        names+=("''${BASH_REMATCH[2]}")
        ports+=("''${BASH_REMATCH[3]}")
        shift
      done
      [ "''${1:-}" = "--" ] || fail "ожидался разделитель --"
      shift
      [ "$#" -gt 0 ] || fail "нет команды"
      rest=("$@")
    }

    # Режим по умолчанию (AI-SBX-5, AI-SEC-6): offline — под корнем рабочих деревьев
    # из файла пользователя или при маркере проекта `.ai/offline`; иначе online.
    # Облако включает только человек флагом запуска (AI-SEC-5), здесь флага нет.
    mode_of() {
      local project=$1 roots=$2 real root
      real=$(realpath -- "$project")
      [ -e "$project/.ai/offline" ] && { echo offline; return; }
      if [ -r "$roots" ]; then
        while IFS= read -r root || [ -n "$root" ]; do
          root=''${root%%#*}
          root=''${root#"''${root%%[![:space:]]*}"}
          root=''${root%"''${root##*[![:space:]]}"}
          [ -n "$root" ] || continue
          root=''${root/#\~/$HOME}
          root=$(realpath -m -- "$root")
          [ "$root" = "/" ] && continue
          case "$real" in "$root" | "$root"/*) echo offline; return ;; esac
        done < "$roots"
      fi
      echo online
    }

    cmd=''${1:-}
    [ "$#" -gt 0 ] && shift
    case "$cmd" in
      mode)
        [ "$#" -eq 2 ] || fail "usage: agents-net mode <проект> <файл корней>"
        mode_of "$1" "$2"
        ;;

      host)
        parse "$@"
        dir=$(mktemp -d "''${XDG_RUNTIME_DIR:-/tmp}/agents-bridge.XXXXXX")
        mkdir -m 0700 "$dir/fwd" "$dir/rev"
        pids=()
        # shellcheck disable=SC2329  # вызывается через trap
        cleanup() {
          local p
          for p in ''${pids[@]+"''${pids[@]}"}; do
            # Группа процессов: socat с `fork` оставляет детей на живых соединениях.
            kill -TERM -- "-$p" 2>/dev/null || true
          done
          rm -rf "$dir"
        }
        trap cleanup EXIT
        for i in "''${!kinds[@]}"; do
          case "''${kinds[$i]}" in
            fwd)
              setsid socat "UNIX-LISTEN:$dir/fwd/''${names[$i]}.sock,fork,mode=0600" "TCP:127.0.0.1:''${ports[$i]}" &
              pids+=("$!")
              wait_bridge "$!" test -S "$dir/fwd/''${names[$i]}.sock" || fail "мост ''${names[$i]} не поднялся"
              ;;
            rev)
              setsid socat "TCP-LISTEN:''${ports[$i]},bind=127.0.0.1,reuseaddr,fork" "UNIX-CONNECT:$dir/rev/''${names[$i]}.sock" &
              pids+=("$!")
              wait_bridge "$!" listening "''${ports[$i]}" || fail "порт ''${ports[$i]} хоста занят или мост ''${names[$i]} не поднялся"
              ;;
          esac
        done
        export AGENTS_NET_DIR=$dir
        rc=0
        "''${rest[@]}" || rc=$?
        exit "$rc"
        ;;

      inside)
        parse "$@"
        for i in "''${!kinds[@]}"; do
          case "''${kinds[$i]}" in
            fwd)
              socat "TCP-LISTEN:''${ports[$i]},bind=127.0.0.1,reuseaddr,fork" "UNIX-CONNECT:$bridge_root/fwd/''${names[$i]}.sock" &
              wait_bridge "$!" listening "''${ports[$i]}" || fail "внутренний мост ''${names[$i]} не поднялся"
              ;;
            rev)
              socat "UNIX-LISTEN:$bridge_root/rev/''${names[$i]}.sock,fork,mode=0600" "TCP:127.0.0.1:''${ports[$i]}" &
              wait_bridge "$!" test -S "$bridge_root/rev/''${names[$i]}.sock" || fail "внутренний мост ''${names[$i]} не поднялся"
              ;;
          esac
        done
        exec "''${rest[@]}"
        ;;

      *)
        fail "usage: agents-net <mode|host|inside> ..."
        ;;
    esac
  '';
}
