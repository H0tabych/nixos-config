# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# AI-SBX-7: агент работает в отдельной ветке или worktree, не в текущем
# чекауте пользователя; слияние в основную ветку — только человек; push по
# умолчанию запрещён. Реализовано ЛОКАЛЬНЫМ КЛОНОМ, а не `git worktree`:
# связанный worktree делит .git с исходным репозиторием — коммиты агента
# писали бы объекты прямо в репозиторий пользователя, а значит пришлось бы
# открывать песочнице `repo_root/.git` на запись (возврат к тому, от чего
# AI-SBX-7 защищает). Клон — независимая копия; `git clone <локальный путь>`
# на одной файловой системе использует hardlink'и для объектов автоматически
# (git-clone(1)) — быстро и без сети; не измерено на большом репозитории,
# ПРОВЕРИТЬ при появлении такого.
#
# Не видит незакоммиченные правки исходного рабочего дерева — клон
# воспроизводит только закоммиченное на HEAD. Осознанное ограничение: агент
# стартует с чистого состояния, а не с неизвестно какими правками в процессе;
# закоммитьте то, что агент должен видеть, прежде чем его звать.
#
# Повторный запуск той же роли на том же репозитории переиспользует уже
# существующие клон и ветку (путь детерминирован хэшем пути репозитория) —
# не плодит клон на каждый вызов. Синхронизация с репозиторием пользователя,
# если тот ушёл вперёд, — вручную (`git fetch`/`rebase` внутри клона);
# автосинхронизация не делается, чтобы не переписывать историю агента без
# спроса.
#
# push «запрещён» здесь — AI-SBX-8-подобное ограждение (pre-push хук), не
# граница безопасности: сам клон внутри песочницы доступен агенту на запись,
# и ничто не мешает ему снять хук. Настоящая граница против push в реальный
# remote — это AI-SBX-2 (ключи SSH/GPG вне домашнего каталога недостижимы);
# для роли в режиме AI-SBX-12, где каталог открыт, хук — единственная
# защита, и это явно слабее, чем для строгих ролей.
{ pkgs }:
pkgs.writeShellApplication {
  name = "agents-git-isolate";
  runtimeInputs = [
    pkgs.git
    pkgs.direnv
  ];
  text = ''
    usage() {
      echo "usage: agents-git-isolate <role> <state-dir> <cwd>" >&2
      exit 1
    }
    [ "$#" -eq 3 ] || usage
    role=$1
    state_dir=$2
    cwd=$3

    if ! git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      # Не git-репозиторий — AI-SBX-7 неприменим, работаем как есть.
      printf '%s\n' "$cwd"
      exit 0
    fi

    repo_root=$(git -C "$cwd" rev-parse --show-toplevel)

    # Уже внутри собственного клона агента (повторный вызов изнутри него) —
    # не оборачиваем повторно.
    case "$repo_root" in
      "$state_dir"/repos/*)
        printf '%s\n' "$cwd"
        exit 0
        ;;
    esac

    rel=$(realpath --relative-to="$repo_root" "$cwd")
    repo_hash=$(printf '%s' "$repo_root" | sha256sum | cut -c1-16)
    clone_dir="$state_dir/repos/$repo_hash"

    if [ ! -d "$clone_dir/.git" ]; then
      mkdir -p "$state_dir/repos"
      echo "agent-launcher: первый запуск для $repo_root — клонирую в $clone_dir (AI-SBX-7)" >&2
      git clone --quiet "$repo_root" "$clone_dir" >&2
      branch="agent/$role/$(date +%Y%m%d-%H%M%S)"
      git -C "$clone_dir" checkout --quiet -b "$branch" >&2

      # AI-SBX-4: direnv хранит разрешения по пути+содержимому (`direnv
      # allow`), а клон — новый путь, даже если .envrc в нём побайтово
      # совпадает с уже одобренным в исходном репозитории — ПРОВЕРЕНО: без
      # этого direnv блокировал .envrc клона и срывал активацию окружения.
      # Доверие переносим автоматически: человек уже одобрил именно это
      # содержимое в исходном репозитории, клон содержит ровно его (на
      # момент HEAD, см. шапку файла про незакоммиченные правки).
      if [ -f "$clone_dir/.envrc" ]; then
        direnv allow "$clone_dir" >&2 2>&1 || true
      fi

      hooks_dir="$clone_dir/.git/agent-hooks"
      mkdir -p "$hooks_dir"
      {
        printf '%s\n' "#!/bin/sh"
        printf '%s\n' 'echo "agent-launcher: push из песочницы запрещён по умолчанию (AI-SBX-7)." >&2'
        printf '%s\n' 'echo "Слияние и публикация — вручную, человеком, вне песочницы." >&2'
        printf '%s\n' "exit 1"
      } > "$hooks_dir/pre-push"
      chmod +x "$hooks_dir/pre-push"
      git -C "$clone_dir" config core.hooksPath "$hooks_dir" >&2

      echo "agent-launcher: ветка $branch; слияние вручную — cd $clone_dir && git log" >&2
    else
      branch=$(git -C "$clone_dir" rev-parse --abbrev-ref HEAD)
      echo "agent-launcher: переиспользую клон $clone_dir (ветка $branch)" >&2
    fi

    target="$clone_dir/$rel"
    # Путь мог не попасть в клон (например, cwd — незакоммиченный каталог):
    # создаём, а не падаем — AI-SBX-6 про отказ самой песочницы, не про это.
    mkdir -p "$target"
    printf '%s\n' "$target"
  '';
}
