# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Лаунчер-песочница (AI_SUBSYSTEM.md §3.4, «Лаунчер-песочница»): единая точка
# истины для bubblewrap-изоляции агентов — используется и фичей
# (agents-tools.nix), и тестом (tests/agent-sandbox.nix), чтобы проверять
# ровно тот код, который реально запускается (AI-SBX-11).
#
# Сетевые режимы `online`/`offline` (AI-SBX-5) принимаются как аргумент, но
# самой сетевой изоляции (netns + разрешить только loopback инференса) здесь
# нет — общий netns с хостом. Документ сам помечает механизм «ПРОВЕРИТЬ»;
# решено отдельной инженерной задачей после R8.6 (ROADMAP.md).
#
# AI-SBX-2: замыкание системы read-only (`--ro-bind / /`), настоящий $HOME
# скрыт `--tmpfs` (значит, ~/.ssh, ~/.gnupg и репозиторий nixos-config — он
# лежит под $HOME на этом хосте — недостижимы одним приёмом); запись —
# только `project-dir` и `state-dir`, оба передаются вызывающим явно.
# `~/.config` возвращается отдельно, но только на чтение: там живут конфиги
# агентов из dotfiles (AI-AGT-3) и машинный слой (DOT-5) — без этого агент не
# смог бы прочитать собственные настройки; секретов там нет (SEC-4, секреты —
# sops/`/run/secrets`, отдельный путь).
# AI-SBX-10: `/run/docker.sock` маскируется bind'ом /dev/null — ro-bind сам
# по себе НЕ блокирует connect() на unix-сокет, поэтому маскировка нужна
# отдельно, даже если сокета на хосте ещё нет (bind-try).
{ pkgs }:
pkgs.writeShellApplication {
  name = "agents-sandbox-exec";
  runtimeInputs = [ pkgs.bubblewrap ];
  text = ''
    usage() {
      echo "usage: agents-sandbox-exec <project-dir> <state-dir> <online|offline> [--env NAME=VALUE]... [--app-path PATH]... [--home-rw] -- <cmd...>" >&2
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

    # --env — явный белый список доплат к окружению со стороны вызывающего
    # (agent-launcher, тот же владелец Nix — AI-SBX-11), для путей к
    # конфигам ролей из dotfiles (AI-AGT-3): эти значения не из проекта,
    # поэтому AI-SBX-9 не нарушается.
    # --app-path — собственный каталог (или файл) приложения, открываемый ему
    # на запись: AI_SUBSYSTEM.md §2.5, секреты класса D — «токены, которые
    # приложение само сохраняет при входе: лаунчер открывает приложению
    # ТОЛЬКО его каталог». Сюда попадают ~/.claude и ~/.claude.json и
    # подобное: сессии, плагины, список MCP и собственная авторизация агента.
    # Это не обход AI-SBX-2: список задаёт лаунчер (владение Nix, AI-SBX-11),
    # он закрыт, и в нём нет ни ~/.ssh, ни ~/.gnupg, ни репозитория
    # конфигурации, ни чужих домашних каталогов.
    # --home-rw — ОСЛАБЛЕННЫЙ режим: домашний каталог не скрывается и доступен
    # на запись целиком. Включается не здесь, а вызывающим — по роли агента
    # (решение пользователя 2026-10-29, AI_SUBSYSTEM.md §3.4 AI-SBX-12 и
    # оговорки в AI-A7/AI-A8). Что остаётся от изоляции в этом режиме:
    # запись вне $HOME по-прежнему запрещена, сокет контейнерного рантайма
    # замаскирован, пространства имён PID/IPC/UTS/cgroup отдельные. Что
    # теряется: ключи SSH/GPG, репозиторий конфигурации и прочее в $HOME
    # становятся доступны агенту на чтение И запись.
    extra_env=()
    app_paths=()
    home_rw=0
    while :; do
      case "''${1:-}" in
        --env)
          extra_env+=("$2")
          shift 2
          ;;
        --app-path)
          app_paths+=("$2")
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
    # project-dir не создаём: несуществующий путь — ошибка вызывающего, а
    # не повод тихо его завести (AI-SBX-6 — фейл-клоуз без скрытых побочных
    # эффектов). state-dir — каталог состояния самого агента, его можно
    # создать по требованию.
    mkdir -p "$state_dir"

    # AI-SBX-2, fail-closed (AI-SBX-6): `--bind project_dir` идёт ПОСЛЕ
    # `--tmpfs real_home`, поэтому домашний каталог (или любой его предок)
    # в роли project_dir перекрыл бы tmpfs и вернул агенту настоящий $HOME
    # на чтение-запись — вместе с ~/.ssh, ~/.gnupg и репозиторием
    # конфигурации. ПРОВЕРЕНО: без этой проверки `agent-launcher` из ~
    # давал агенту прочитать ~/.ssh/. Запуск из такого каталога запрещён,
    # а не «обёрнут» перестановкой флагов: рабочее дерево проекта и
    # домашний каталог — разные вещи по смыслу (AI-SBX-7).
    # В режиме --home-rw проверка не нужна: домашний каталог там открыт
    # намеренно, скрывать его нечем и незачем (корень `/` всё равно запрещён).
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

    # HOME остаётся НАСТОЯЩИМ путём, хотя сам каталог подменён на tmpfs
    # (AI-SBX-2: домашний каталог скрыт — внутри он пустой). Иначе `~/...` в
    # приложении раскрывался бы в state_dir и не совпадал с путями, по
    # которым смонтированы его собственные каталоги (--app-path) — ПРОВЕРЕНО:
    # при HOME=state_dir агент не находил ни ~/.claude.json, ни ~/.claude.
    # Всё, что приложение пишет в $HOME помимо своих каталогов, попадает в
    # tmpfs и исчезает с завершением — это намеренно.
    env_args=(
      "HOME=$real_home"
      "PATH=$PATH"
      "TERM=''${TERM:-xterm-256color}"
    )
    [ -n "''${LANG:-}" ] && env_args+=("LANG=$LANG")

    # NET-10/L-7: переменные прокси определяются в ОДНОМ месте (сессия, режим
    # M1 — session-hyprland.nix) — здесь они только пробрасываются, не
    # задаются. Это явный белый список, который AI-SBX-3 разрешает; без них
    # `env -i` отрезал агента от туннеля, и запрос уходил напрямую (ПРОВЕРЕНО:
    # claude-code получал 403 от api.anthropic.com с прямого адреса, тогда как
    # тот же пакет вне песочницы работал, унаследовав прокси из сессии).
    # Значения — адреса loopback, не секреты (сеть у песочницы общая с хостом,
    # см. AI-SBX-5/ПРОВЕРИТЬ выше).
    for v in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY; do
      if [ -n "''${!v:-}" ]; then
        env_args+=("$v=''${!v}")
      fi
    done
    [ -n "''${AI_GATEWAY_URL:-}" ] && env_args+=("AI_GATEWAY_URL=$AI_GATEWAY_URL")
    [ -n "''${AI_GATEWAY_ACCESS_KEY_FILE:-}" ] && env_args+=("AI_GATEWAY_ACCESS_KEY_FILE=$AI_GATEWAY_ACCESS_KEY_FILE")
    if [ "''${#extra_env[@]}" -gt 0 ]; then
      env_args+=("''${extra_env[@]}")
    fi

    bwrap_args=(
      --unshare-pid
      --unshare-ipc
      --unshare-uts
      --unshare-cgroup
      --die-with-parent
      --ro-bind / /
      --dev /dev
      --proc /proc
      --tmpfs /tmp
    )

    if [ "$home_rw" -eq 1 ]; then
      # Ослабленный режим (см. --home-rw выше): домашний каталог не
      # подменяется, а открывается на запись целиком. Отдельные bind'ы для
      # ~/.config, direnv и --app-path не нужны — всё это уже внутри $HOME.
      bwrap_args+=(--bind "$real_home" "$real_home")
    else
      bwrap_args+=(
        --tmpfs "$real_home"
        --ro-bind-try "$real_home/.config" "$real_home/.config"
        # AI-SBX-4: проектное окружение активирует env-manager (direnv) уже
        # внутри песочницы, а он отказывается работать, если не видит своей
        # базы разрешений — `.envrc is blocked` (ПРОВЕРЕНО живьём: без этого
        # агент вообще не стартовал в любом проекте с .envrc). Только чтение:
        # выдавать разрешения — дело человека вне песочницы.
        --ro-bind-try "''${XDG_DATA_HOME:-$real_home/.local/share}/direnv" \
        "''${XDG_DATA_HOME:-$real_home/.local/share}/direnv"
      )
    fi

    bwrap_args+=(
      --bind "$project_dir" "$project_dir"
      --bind "$state_dir" "$state_dir"
      --chdir "$project_dir"
    )
    # Собственные каталоги приложения (см. --app-path выше). Идут ПОСЛЕ
    # `--tmpfs real_home`, иначе tmpfs затёр бы их; `-try`, потому что при
    # первом запуске каталога может ещё не быть — его создаст само приложение
    # внутри tmpfs, и это не повод падать.
    for p in ''${app_paths[@]+"''${app_paths[@]}"}; do
      bwrap_args+=(--bind-try "$p" "$p")
    done

    # AI-SBX-10: сокет рантайма контейнеров не бинден на чтение-запись — он
    # маскируется, даже если группа docker каким-то образом унаследована.
    if [ -e /run/docker.sock ]; then
      bwrap_args+=(--bind /dev/null /run/docker.sock)
    fi

    # AI-SBX-6 (fail-closed): ничего после этой строки — любая ошибка bwrap
    # (включая недоступность непривилегированных пользовательских
    # пространств имён, AI-SBX-11) останавливает скрипт `set -euo pipefail`
    # до исполнения целевой команды.
    exec env -i "''${env_args[@]}" bwrap "''${bwrap_args[@]}" -- "$@"
  '';
}
