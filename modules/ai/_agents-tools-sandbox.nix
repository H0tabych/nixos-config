# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Лаунчер-песочница (AI_SUBSYSTEM.md §3.4, «Лаунчер-песочница»): единая точка
# истины для bubblewrap-изоляции агентов — используется и фичей
# (agents-tools.nix), и тестом (tests/agent-sandbox.nix), чтобы проверять
# ровно тот код, который реально запускается (AI-SBX-11).
#
# Сетевые режимы `online`/`offline` (AI-SBX-5) принимаются как аргумент, но
# самой сетевой изоляции здесь нет — общий netns с хостом; отдельное
# пространство имён и мосты — R9.17.
#
# AI-SBX-1 (ADR-44, R9.14): корень файловой системы СОБИРАЕТСЯ из
# разрешённого, а не берётся с хоста с масками (`--ro-bind / /` оставлял
# видимыми сокеты сессии, системную шину, /run/secrets* и любой новый сокет
# хоста — D17). Только чтение: хранилище пакетов, сокет демона сборки, /etc,
# /run/current-system, /bin/sh, /usr/bin/env. Свои: /dev, /proc, /tmp, /run
# (пустой, внутри только свой XDG_RUNTIME_DIR). Всё, чего нет в перечне,
# внутри не существует — в том числе /run/docker.sock (AI-SBX-10) и
# `/run/user/<uid>` хоста.
# AI-SBX-2: домашний каталог скрыт `--tmpfs`; из ~/.config возвращаются только
# каталоги белого списка (машинный слой, ai, git, direnv + каталоги роли из
# `--config`), каждый отдельным ro-bind (симлинк в dotfiles разрешает ядро).
# Запись — только `project-dir` и `state-dir`, оба передаются вызывающим явно.
# У роли свои XDG_CACHE/STATE/DATA_HOME внутри state-dir.
# AI-SBX-7 (ADR-44, R9.15): работа на месте. Проект — на запись, метаданные git
# и `.envrc` — только чтение, общий git-каталог привязан к себе (список даёт
# `agents-git binds`). `.direnv` у роли свой (в state-dir). Отчёт — `agents-git`.
# AI-SBX-3: окружение пересобирается с нуля (`env -i`); ключ доступа к шлюзу
# попадает значением через `--pass-env` (из окружения самого процесса, не из
# argv — не виден в `ps`), путь к файлу с ключом не пробрасывается.
{ pkgs, gitTool }:
pkgs.writeShellApplication {
  name = "agents-sandbox-exec";
  runtimeInputs = [
    pkgs.bubblewrap
    gitTool
  ];
  text = ''
    usage() {
      echo "usage: agents-sandbox-exec <project-dir> <state-dir> <online|offline> [--env NAME=VALUE]... [--pass-env NAME]... [--config NAME]... [--app-path PATH]... [--cwd PATH] [--home-rw] -- <cmd...>" >&2
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

    # --env — явная доплата к окружению от вызывающего (agent-launcher, тот
    # же владелец Nix — AI-SBX-11): значения не из проекта (AI-SBX-9).
    # --pass-env — то же, но значение берётся из окружения самого процесса
    # (ключ доступа к шлюзу: в argv ему не место).
    # --config — каталог роли в ~/.config (белый список AI-SBX-2), только чтение.
    # --app-path — собственный каталог (или файл) приложения на запись
    # (§2.5, класс D: токены, которые приложение само сохраняет при входе).
    # --cwd — рабочий каталог внутри project-dir (по умолчанию он сам).
    # --home-rw — ОСЛАБЛЕННЫЙ режим (AI-SBX-12, решение владельца по роли):
    # $HOME открыт на запись целиком; корень из разрешённого, сокеты сессии и
    # секреты шлюза остаются недоступны, запись вне $HOME запрещена. Теряются
    # ключи SSH/GPG, ключ расшифровки секретов, репозиторий конфигурации и
    # прочее содержимое $HOME.
    extra_env=()
    pass_env=()
    config_dirs=()
    app_paths=()
    cwd_arg=""
    home_rw=0
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
        *) break ;;
      esac
    done
    [ "''${1:-}" = "--" ] || usage
    shift

    real_home="$HOME"
    uid=$(id -u)
    # project-dir не создаём: несуществующий путь — ошибка вызывающего, а не
    # повод тихо его завести (AI-SBX-6). Каталог состояния роли и её XDG-каталоги
    # создаём по требованию.
    mkdir -p "$state_dir/cache" "$state_dir/state" "$state_dir/data"

    # AI-SBX-2, fail-closed (AI-SBX-6): `--bind project_dir` идёт ПОСЛЕ
    # `--tmpfs real_home`, поэтому домашний каталог (или его предок) в роли
    # project_dir вернул бы агенту настоящий $HOME на запись. ПРОВЕРЕНО: без
    # проверки `agent-launcher` из ~ давал прочитать ~/.ssh/. Корень `/`
    # запрещён всегда; в --home-rw $HOME открыт намеренно.
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

    # HOME остаётся НАСТОЯЩИМ путём (внутри — пустой tmpfs), иначе `~/...`
    # приложения не совпал бы с путями его каталогов (--app-path; ПРОВЕРЕНО
    # живьём). XDG_* — свои у роли (ADR-44); XDG_CONFIG_HOME не задаём:
    # конфиги — белый список в настоящем ~/.config.
    env_args=(
      "HOME=$real_home"
      "PATH=$PATH"
      "TERM=''${TERM:-xterm-256color}"
      "XDG_CACHE_HOME=$state_dir/cache"
      "XDG_STATE_HOME=$state_dir/state"
      "XDG_DATA_HOME=$state_dir/data"
      "XDG_RUNTIME_DIR=/run/user/$uid"
    )
    [ -n "''${LANG:-}" ] && env_args+=("LANG=$LANG")

    # NET-10/L-7: переменные прокси определяются в ОДНОМ месте (сессия, M1) —
    # здесь только пробрасываются; без них `env -i` уводил агента мимо туннеля
    # (ПРОВЕРЕНО: 403 от api.anthropic.com). Значения — адреса loopback.
    for v in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY; do
      if [ -n "''${!v:-}" ]; then
        env_args+=("$v=''${!v}")
      fi
    done
    [ -n "''${AI_GATEWAY_URL:-}" ] && env_args+=("AI_GATEWAY_URL=$AI_GATEWAY_URL")
    for v in ''${pass_env[@]+"''${pass_env[@]}"}; do
      [ -n "''${!v:-}" ] && env_args+=("$v=''${!v}")
    done
    if [ "''${#extra_env[@]}" -gt 0 ]; then
      env_args+=("''${extra_env[@]}")
    fi

    # Голый корень bwrap — tmpfs; всё ниже — перечень разрешённого (AI-SBX-1).
    # /bin/sh и /usr/bin/env — симлинками на их цели в хранилище.
    bwrap_args=(
      --unshare-pid
      --unshare-ipc
      --unshare-uts
      --unshare-cgroup
      --die-with-parent
      --ro-bind /nix/store /nix/store
      --ro-bind-try /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket
      --ro-bind /etc /etc
      --dev /dev
      --proc /proc
      --tmpfs /tmp
      # Порядок важен: tmpfs /run затирает всё, что смонтировано в него раньше.
      --tmpfs /run
      --ro-bind-try /run/current-system /run/current-system
      --perms 0700 --dir "/run/user/$uid"
    )
    for f in /bin/sh /usr/bin/env; do
      if [ -e "$f" ]; then
        bwrap_args+=(--symlink "$(readlink -f "$f")" "$f")
      fi
    done

    # Каталог direnv с базой разрешений (AI-SBX-4): direnv ищет её в
    # $XDG_DATA_HOME/direnv, а он теперь свой — настоящую базу кладём туда, ro.
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

    # AI-SBX-7: список монтирований защиты git даёт `agents-git binds`; через
    # файл (не подстановку процесса), чтобы отказ останавливал запуск (set -e).
    git_binds_file=$(mktemp)
    agents-git binds "$project_dir" "$project_real" > "$git_binds_file"
    mapfile -d "" -t git_bind_args < "$git_binds_file"
    bwrap_args+=(''${git_bind_args[@]+"''${git_bind_args[@]}"})
    for p in ''${app_paths[@]+"''${app_paths[@]}"}; do
      bwrap_args+=(--bind-try "$p" "$p")
    done

    # Маска состояния шлюза (D17): в --home-rw $HOME открыт, а там лежит
    # config.json шлюза с ключами провайдера. Убрать в R9.16 (шлюз станет
    # системной службой, состояние уйдёт из $HOME). `-d`: bwrap не должен
    # создавать заглушку в настоящем $HOME.
    gw_state="''${XDG_STATE_HOME:-$real_home/.local/state}/llm-gateway"
    if [ "$home_rw" -eq 1 ] && [ -d "$gw_state" ]; then
      bwrap_args+=(--tmpfs "$gw_state")
    fi

    # AI-SBX-6 (fail-closed): любая ошибка bwrap (в том числе недоступность
    # пользовательских пространств имён, AI-SBX-11) останавливает скрипт
    # (`set -e`) до исполнения целевой команды.
    rm -f "$git_binds_file"
    exec env -i "''${env_args[@]}" bwrap "''${bwrap_args[@]}" -- "$@"
  '';
}
