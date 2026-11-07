# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Лаунчер-песочница (AI_SUBSYSTEM.md §3.4): единая точка истины для
# bubblewrap-изоляции агентов — её используют и фича (agents-tools.nix), и тесты
# (tests/agent-sandbox.nix, agent-network.nix): проверяется тот код, что реально
# запускается (AI-SBX-11).
#
# AI-SBX-1 (R9.14): корень СОБИРАЕТСЯ из разрешённого, а не берётся с хоста с
# масками (D17). Только чтение: хранилище пакетов, /etc, /run/current-system,
# /bin/sh, /usr/bin/env, stub-resolv.conf, сокет демона сборки (только `online`).
# Свои: /dev, /proc, /tmp, /run (внутри только свой XDG_RUNTIME_DIR); ни
# /run/docker.sock (AI-SBX-10), ни `/run/user/<uid>` хоста.
# AI-SBX-2: $HOME скрыт `--tmpfs`; из ~/.config — только белый список (machine.d,
# ai, git, direnv + `--config`), ro. Запись — `project-dir` и `state-dir`; у роли
# свои XDG_CACHE/STATE/DATA_HOME внутри state-dir.
# AI-SBX-3: окружение с нуля (`env -i`); ключ шлюза — значением через `--pass-env`.
# AI-SBX-5 (R9.17): свой пустой netns; наружу — только мосты `--bridge`
# (`agents-net`). `online`: внутри прокси на мост `proxy`; `offline`: ни прокси,
# ни сокета демона сборки.
# AI-SBX-7 (R9.15): работа на месте; метаданные git и `.envrc` ro, список —
# `agents-git binds`; `.direnv` у роли свой.
{
  pkgs,
  gitTool,
  netTool,
}:
pkgs.writeShellApplication {
  name = "agents-sandbox-exec";
  runtimeInputs = [
    pkgs.bubblewrap
    gitTool
    netTool
  ];
  text = ''
    usage() {
      echo "usage: agents-sandbox-exec <project-dir> <state-dir> <online|offline> [--env NAME=VALUE]... [--pass-env NAME]... [--config NAME]... [--app-path PATH]... [--cwd PATH] [--home-rw] [--bridge fwd|rev:NAME:PORT]... -- <cmd...>" >&2
      exit 1
    }

    [ "$#" -ge 4 ] || usage
    project_dir=$1
    state_dir=$2
    mode=$3
    shift 3

    case "$mode" in
      online | offline) ;;
      *) usage ;;
    esac

    # --env — доплата к окружению от вызывающего (значения не из проекта, AI-SBX-9);
    # --pass-env — то же, но значение из окружения процесса (ключ шлюза: не в argv);
    # --config — каталог роли в ~/.config (белый список), ro; --app-path — свой
    # каталог приложения на запись (§2.5, класс D); --cwd — рабочий каталог внутри
    # project-dir; --bridge — мост в netns (AI-SBX-5, спецификация как у `agents-net`,
    # каталог сокетов — $AGENTS_NET_DIR от `agents-net host`). --home-rw — ОСЛАБЛЕННЫЙ режим (AI-SBX-12): $HOME на запись
    # целиком; корень из разрешённого и сокеты сессии/секреты шлюза недоступны
    # по-прежнему, теряются ключи SSH/GPG, ключ расшифровки, репозиторий
    # конфигурации и прочее содержимое $HOME.
    extra_env=()
    pass_env=()
    config_dirs=()
    app_paths=()
    cwd_arg=""
    home_rw=0
    bridge_dir="''${AGENTS_NET_DIR:-}"
    bridges=()
    while :; do
      case "''${1:-}" in
        --env)
          extra_env+=("$2")
          shift 2
          ;;
        --pass-env)
          [[ "$2" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || usage
          pass_env+=("$2")
          shift 2
          ;;
        --config)
          # Имя каталога, не путь: выйти из ~/.config нельзя.
          case "$2" in "" | . | .. | */*) usage ;; esac
          config_dirs+=("$2")
          shift 2
          ;;
        --app-path)
          app_paths+=("$2")
          shift 2
          ;;
        --cwd)
          cwd_arg="$2"
          shift 2
          ;;
        --home-rw)
          home_rw=1
          shift
          ;;
        --bridge)
          bridges+=("$2")
          shift 2
          ;;
        *) break ;;
      esac
    done
    [ "''${1:-}" = "--" ] || usage
    shift
    # Мосты без каталога сокетов — ошибка вызывающего.
    { [ -n "$bridge_dir" ] || [ "''${#bridges[@]}" -eq 0 ]; } || usage
    real_home="$HOME"
    uid=$(id -u)
    # project-dir не создаём: несуществующий путь — ошибка вызывающего (AI-SBX-6).
    mkdir -p "$state_dir/cache" "$state_dir/state" "$state_dir/data"

    # AI-SBX-2, fail-closed: `--bind project_dir` идёт ПОСЛЕ `--tmpfs real_home`,
    # поэтому $HOME (или его предок) в роли project_dir вернул бы агенту настоящий
    # $HOME на запись (ПРОВЕРЕНО: читался ~/.ssh/). `/` запрещён всегда; в
    # --home-rw $HOME открыт намеренно.
    project_real=$(realpath -- "$project_dir")
    home_real=$(realpath -- "$real_home")
    if [ "$project_real" = "/" ] || { [ "$home_rw" -eq 0 ] && {
      [ "$project_real" = "$home_real" ] ||
        case "$home_real" in "$project_real"/*) true ;; *) false ;; esac
    }; }; then
      echo "agents-sandbox-exec: project-dir ($project_real) — домашний каталог, его предок или корень;" >&2
      echo "  запуск запрещён (AI-SBX-2: это открыло бы агенту секреты и ключи)." >&2
      echo "  Перейдите в каталог конкретного проекта и повторите." >&2
      exit 1
    fi

    # --cwd обязан лежать внутри project-dir (иначе chdir вывел бы в пустой tmpfs).
    cwd_real="$project_real"
    if [ -n "$cwd_arg" ]; then
      cwd_real=$(realpath -- "$cwd_arg")
      case "$cwd_real" in
        "$project_real" | "$project_real"/*) ;;
        *)
          echo "agents-sandbox-exec: --cwd ($cwd_real) вне project-dir ($project_real)" >&2
          exit 1
          ;;
      esac
    fi

    # HOME — НАСТОЯЩИЙ путь (внутри пустой tmpfs), иначе `~/...` не совпал бы с
    # --app-path (ПРОВЕРЕНО). XDG_* — свои у роли; XDG_CONFIG_HOME не задаём.
    env_args=(
      "HOME=$real_home"
      "PATH=$PATH"
      "TERM=''${TERM:-xterm-256color}"
      "XDG_CACHE_HOME=$state_dir/cache"
      "XDG_STATE_HOME=$state_dir/state"
      "XDG_DATA_HOME=$state_dir/data"
      "XDG_RUNTIME_DIR=/run/user/$uid"
      # bwrap создаёт /nix/var/nix/db пустым и записываемым, `auto` выбрал бы
      # локальное хранилище и упал на ro /nix/store (ПРОВЕРЕНО на машине); в
      # offline демона нет — nix сразу отказывает, без попыток сети.
      "NIX_REMOTE=daemon"
    )
    [ -n "''${LANG:-}" ] && env_args+=("LANG=$LANG")

    # Выход в сеть только через мост `proxy` (HTTP-вход туннеля, NET-7): адрес
    # внутри тот же, что у хоста, переменные хоста не пробрасываются (в M2 их нет).
    proxy_port=""
    for b in ''${bridges[@]+"''${bridges[@]}"}; do
      [[ "$b" =~ ^fwd:proxy:([0-9]+)$ ]] && proxy_port="''${BASH_REMATCH[1]}"
    done
    if [ -n "$proxy_port" ]; then
      for v in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY; do
        env_args+=("$v=http://127.0.0.1:$proxy_port")
      done
      for v in no_proxy NO_PROXY; do
        env_args+=("$v=localhost,127.0.0.1,::1")
      done
    fi
    [ -n "''${AI_GATEWAY_URL:-}" ] && env_args+=("AI_GATEWAY_URL=$AI_GATEWAY_URL")
    for v in ''${pass_env[@]+"''${pass_env[@]}"}; do
      [ -n "''${!v:-}" ] && env_args+=("$v=''${!v}")
    done
    if [ "''${#extra_env[@]}" -gt 0 ]; then
      env_args+=("''${extra_env[@]}")
    fi

    # Голый корень bwrap — tmpfs; ниже — перечень разрешённого (AI-SBX-1).
    bwrap_args=(
      --unshare-pid
      --unshare-ipc
      --unshare-uts
      --unshare-cgroup
      --unshare-net
      --die-with-parent
      --ro-bind /nix/store /nix/store
      --ro-bind /etc /etc
      --dev /dev
      --proc /proc
      --tmpfs /tmp
      # Порядок важен: tmpfs /run затирает всё, что смонтировано в него раньше.
      --tmpfs /run
      --ro-bind-try /run/current-system /run/current-system
      --ro-bind-try /run/systemd/resolve/stub-resolv.conf /run/systemd/resolve/stub-resolv.conf
      --perms 0700 --dir "/run/user/$uid"
    )
    # Сокет демона сборки — канал выхода (загрузки с фиксированным хэшем), в offline скрыт.
    [ "$mode" = online ] && bwrap_args+=(--ro-bind-try /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket)
    [ -z "$bridge_dir" ] || bwrap_args+=(
      --ro-bind "$bridge_dir/fwd" /run/agents-bridge/fwd
      --bind "$bridge_dir/rev" /run/agents-bridge/rev
    )
    for f in /bin/sh /usr/bin/env; do
      if [ -e "$f" ]; then
        bwrap_args+=(--symlink "$(readlink -f "$f")" "$f")
      fi
    done

    # База разрешений direnv (AI-SBX-4): ищется в $XDG_DATA_HOME/direnv — кладём ro.
    direnv_data="''${XDG_DATA_HOME:-$real_home/.local/share}/direnv"

    if [ "$home_rw" -eq 1 ]; then
      bwrap_args+=(--bind "$real_home" "$real_home")
    else
      bwrap_args+=(--tmpfs "$real_home")
      for d in machine.d ai git direnv ''${config_dirs[@]+"''${config_dirs[@]}"}; do
        bwrap_args+=(--ro-bind-try "$real_home/.config/$d" "$real_home/.config/$d")
      done
    fi

    # Кэш окружения проекта (AI-SBX-7): у роли свой, по хэшу пути проекта.
    direnv_cache="$state_dir/direnv/$(printf '%s' "$project_real" | sha256sum | cut -c1-16)"
    mkdir -p "$direnv_cache"
    bwrap_args+=(
      --bind "$project_dir" "$project_dir"
      --bind "$state_dir" "$state_dir"
      --bind "$direnv_cache" "$project_dir/.direnv"
      --ro-bind-try "$direnv_data" "$state_dir/data/direnv"
      --chdir "$cwd_real"
    )

    # AI-SBX-7: монтирования защиты git — `agents-git binds`, через файл, чтобы
    # отказ останавливал запуск (set -e).
    git_binds_file=$(mktemp)
    agents-git binds "$project_dir" "$project_real" > "$git_binds_file"
    mapfile -d "" -t git_bind_args < "$git_binds_file"
    bwrap_args+=(''${git_bind_args[@]+"''${git_bind_args[@]}"})
    for p in ''${app_paths[@]+"''${app_paths[@]}"}; do
      bwrap_args+=(--bind-try "$p" "$p")
    done

    # AI-SBX-6 (fail-closed): ошибка bwrap (AI-SBX-11) останавливает скрипт
    # (`set -e`) до исполнения команды. Мосты внутри netns — `agents-net inside`.
    rm -f "$git_binds_file"
    [ "''${#bridges[@]}" -eq 0 ] || set -- agents-net inside "''${bridges[@]}" -- "$@"
    exec env -i "''${env_args[@]}" bwrap "''${bwrap_args[@]}" -- "$@"
  '';
}
