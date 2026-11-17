# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Лаунчер-песочница (AI_SUBSYSTEM.md §3.4): единая точка истины bubblewrap-изоляции агентов —
# её используют и фича, и тесты: проверяется тот код, что реально запускается (AI-SBX-11).
#
# AI-SBX-1 (R9.14): корень СОБИРАЕТСЯ из разрешённого, а не берётся с хоста с
# масками (D17). Только чтение: хранилище пакетов, /etc, /run/current-system,
# /bin/sh, /usr/bin/env, stub-resolv.conf, сокет демона сборки (только `online`).
# Свои: /dev, /proc, /tmp, /run (внутри только свой XDG_RUNTIME_DIR); ни
# /run/docker.sock (AI-SBX-10), ни `/run/user/<uid>` хоста.
# AI-SBX-2: $HOME скрыт `--tmpfs`; из ~/.config — только белый список (machine.d,
# ai, git, direnv + `--config`), ro. Запись — `project-dir` и `state-dir`; у роли
# свои XDG_CACHE/STATE/DATA_HOME внутри state-dir.
# AI-SBX-3: окружение с нуля (`env -i`); ключ шлюза — значением через `--pass-env`;
# `--print-env` — это окружение NUL-потоком без запуска (вход AI-SBX-13, `agents-host enter`).
# AI-SBX-5 (ADR-47, R9.20): сеть даёт охранник (`agents-net guard`: pasta + nftables), он
# выставляет AGENTS_NET_GUARDED=1. Агент во вложенном пространстве пользователя
# (`--unshare-user`) прав над сетевым не имеет и правил не меняет. Без охранника (тесты,
# прямой вызов) — пустой netns (`--unshare-net`). resolv.conf — AGENTS_RESOLV_CONF.
# `online`: есть сокет демона сборки; `offline`: нет.
# AI-SBX-7 (R9.15): работа на месте; метаданные git и `.envrc` ro, список —
# `agents-git binds`; `.direnv` у роли свой.
# AI-SBX-13 (ADR-48): project-dir `-` — без проекта (только с `--home-rw`), долгоживущая
# песочница, в которую входят окна; `--info-file` — JSON `bwrap --info-fd` (id пространств).
{
  pkgs,
  gitTool,
  mounts, # фрагмент bash с монтированиями (AI-SBX-2/7/12) — передаёт владелец
}:
pkgs.writeShellApplication {
  name = "agents-sandbox-exec";
  runtimeInputs = [
    pkgs.bubblewrap
    pkgs.nftables
    gitTool
  ];
  text = ''
    usage() {
      echo "usage: agents-sandbox-exec <project-dir|-> <state-dir> <online|offline> [--env NAME=VALUE]... [--pass-env NAME]... [--config NAME]... [--app-path PATH]... [--cwd PATH] [--home-rw] [--device kvm|dri]... [--info-file PATH] -- <cmd...>" >&2
      echo "       agents-sandbox-exec <project-dir|-> <state-dir> <online|offline> [--env ...] [--pass-env ...] --print-env" >&2
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

    # --env — доплата к окружению от вызывающего (не из проекта, AI-SBX-9); --pass-env — то же,
    # значение из окружения процесса (ключ шлюза: не в argv); --config — каталог роли в ~/.config
    # (белый список), ro; --app-path — свой каталог приложения на запись (§2.5, класс D); --cwd —
    # рабочий каталог внутри project-dir. --home-rw — ОСЛАБЛЕННЫЙ режим (AI-SBX-12): $HOME на запись
    # целиком; корень из разрешённого и сокеты сессии/секреты шлюза недоступны по-прежнему,
    # теряются ключи SSH/GPG, ключ расшифровки, репозиторий конфигурации и прочее в $HOME.
    extra_env=()
    pass_env=()
    devices=()
    config_dirs=()
    app_paths=()
    cwd_arg=""
    home_rw=0 info_file="" print_env=0
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
        --device)
          case "$2" in kvm | dri) devices+=("$2") ;; *) usage ;; esac
          shift 2
          ;;
        --info-file)
          info_file="$2"
          shift 2
          ;;
        --print-env)
          print_env=1
          shift
          ;;
        *) break ;;
      esac
    done
    if [ "$print_env" -eq 0 ]; then
      [ "''${1:-}" = "--" ] || usage
      shift
    fi
    real_home="$HOME"
    # В пространстве охранника `id` — root пространства: настоящие uid/gid идут от `agents-net run`.
    uid=''${AGENTS_HOST_UID:-$(id -u)}
    gid=''${AGENTS_HOST_GID:-$(id -g)}

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

    # Прокси-переменные есть только в M1 (NET-10), в M2 их нет; `all_proxy` (SOCKS) не передаём.
    for v in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY no_proxy NO_PROXY; do
      [ -n "''${!v:-}" ] && env_args+=("$v=''${!v}")
    done
    [ -n "''${AI_GATEWAY_URL:-}" ] && env_args+=("AI_GATEWAY_URL=$AI_GATEWAY_URL")
    for v in ''${pass_env[@]+"''${pass_env[@]}"}; do
      [ -n "''${!v:-}" ] && env_args+=("$v=''${!v}")
    done
    if [ "''${#extra_env[@]}" -gt 0 ]; then
      env_args+=("''${extra_env[@]}")
    fi
    # Окружение для входа в долгоживущую песочницу — в поток, не в argv (ключи, AI-SBX-3).
    if [ "$print_env" -eq 1 ]; then
      mkdir -p "$state_dir/cache" "$state_dir/state" "$state_dir/data"
      printf '%s\0' "''${env_args[@]}"
      exit 0
    fi

    guarded=0
    [ "''${AGENTS_NET_GUARDED:-}" = 1 ] && guarded=1
    resolv_conf=''${AGENTS_RESOLV_CONF:-}
    unset AGENTS_RESOLV_CONF AGENTS_NET_GUARDED AGENTS_HOST_UID AGENTS_HOST_GID
    # AI-SBX-6: охранник заявлен — правила обязаны быть загружены.
    [ "$guarded" -eq 0 ] || nft list table inet agents > /dev/null 2>&1 || {
      echo "agents-sandbox-exec: охранник заявлен, таблицы nftables inet agents нет (AI-SBX-6)" >&2
      exit 1
    }
    mkdir -p "$state_dir/cache" "$state_dir/state" "$state_dir/data"

    no_project=0
    if [ "$project_dir" = "-" ]; then
      # Без проекта песочница имеет смысл только с домашним каталогом (AI-SBX-12, AI-SBX-13).
      [ "$home_rw" -eq 1 ] || usage
      no_project=1
    else
      # project-dir не создаём: несуществующий путь — ошибка вызывающего (AI-SBX-6).
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
    fi

    # Голый корень bwrap — tmpfs; ниже — перечень разрешённого (AI-SBX-1).
    bwrap_args=(
      --unshare-pid
      --unshare-ipc
      --unshare-uts
      --unshare-cgroup
      --unshare-user
      --uid "$uid"
      --gid "$gid"
      --die-with-parent
      --ro-bind /nix/store /nix/store
      --ro-bind /etc /etc
      --dev /dev
      --proc /proc
      --tmpfs /tmp
      # Порядок важен: tmpfs /run затирает всё, что смонтировано в него раньше.
      --tmpfs /run
      --ro-bind-try /run/current-system /run/current-system
      --perms 0700 --dir "/run/user/$uid"
    )
    # Сокет демона сборки — канал выхода (загрузки с фиксированным хэшем), в offline скрыт.
    [ "$mode" = online ] && bwrap_args+=(--ro-bind-try /nix/var/nix/daemon-socket /nix/var/nix/daemon-socket)
    [ "$guarded" -eq 1 ] || bwrap_args+=(--unshare-net)
    # resolv.conf: bwrap не монтирует поверх симлинка — файл кладётся по конечному пути
    # ссылки ПОСЛЕ `--tmpfs /run`, содержимое — дескриптором, исходный файл удаляется.
    if [ -n "$resolv_conf" ]; then
      resolv_target=$(readlink -m /etc/resolv.conf)
      exec 3< "$resolv_conf"
      rm -f -- "$resolv_conf"
      bwrap_args+=(--dir "$(dirname "$resolv_target")" --ro-bind-data 3 "$resolv_target")
    else
      bwrap_args+=(--ro-bind-try /run/systemd/resolve/stub-resolv.conf /run/systemd/resolve/stub-resolv.conf)
    fi
    for f in /bin/sh /usr/bin/env; do
      [ ! -e "$f" ] || bwrap_args+=(--symlink "$(readlink -f "$f")" "$f")
    done
    # AI-SBX-13: сведения о песочнице для входа (pid процесса внутри, id пространств).
    [ -z "$info_file" ] || { exec 4> "$info_file"; bwrap_args+=(--info-fd 4); }

    ${mounts}

    # AI-SBX-6 (fail-closed): ошибка bwrap (AI-SBX-11) останавливает скрипт
    # (`set -e`) до исполнения команды.
    exec env -i "''${env_args[@]}" bwrap "''${bwrap_args[@]}" -- "$@"
  '';
}
