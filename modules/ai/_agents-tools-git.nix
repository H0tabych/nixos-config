# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# AI-SBX-7 (ADR-44): отчёт лаунчера после сессии. Агент работает в текущем
# рабочем дереве и коммитит; метаданные git на запись закрыты песочницей, но
# объекты, ссылки и индекс остаются открытыми — этот отчёт показывает человеку
# то, что `git status` не покажет:
#   - ссылки, сдвинутые, созданные или удалённые вне текущей ветки, и смену
#     самой ветки; `refs/replace`;
#   - флаги индекса `skip-worktree` и `assume-unchanged`;
#   - новые вложенные репозитории (`.git` где угодно ниже корня);
#   - появление `hooks/`, `info/`, `config.worktree` там, где их не было
#     (`--ro-bind-try` в песочнице не создаёт заглушек);
#   - изменённые игнорируемые файлы (`.gitignore` скрывает их от `git status`).
# Это отчёт, а не граница: он сообщает, не откатывает. Слияние и публикация —
# только человек.
#
# Использование:
#   agents-git snapshot <корень> <файл>   — до сессии
#   agents-git report   <корень> <файл>   — после сессии, в stderr
#   agents-git binds <project-dir> <realpath project-dir>
#                                         — аргументы bwrap защиты метаданных
#                                           (NUL-разделители), для песочницы
# Вне git-репозитория snapshot и report ничего не делают.
{ pkgs }:
pkgs.writeShellApplication {
  name = "agents-git";
  runtimeInputs = [
    pkgs.git
    pkgs.coreutils
    pkgs.findutils
    pkgs.diffutils
    pkgs.gnugrep
    pkgs.gawk
  ];
  text = ''
    usage() {
      echo "usage: agents-git <snapshot|report> <root> <file> | binds <project-dir> <project-real>" >&2
      exit 1
    }
    [ "$#" -eq 3 ] || usage
    cmd=$1
    root=$2
    file=$3


    # Защита метаданных git (AI-SBX-7): аргументы bwrap, NUL-разделённые.
    # Общий git-каталог привязан к себе отдельной точкой монтирования (`mv .git`
    # и `rm -r .git` упираются в EBUSY); из метаданных на чтение — config,
    # config.worktree, hooks, info, `.git`-файлы связанных деревьев и подмодулей,
    # их config/hooks/info, указатели worktrees/*/gitdir, каталог core.hooksPath
    # внутри дерева и `.envrc`. `--ro-bind-try`: отсутствующее не создаём.
    binds() {
      local project_dir=$1 project_real=$2
      local ro_paths=() top gitdir common g sm hp entry m p
      add_gitdir_ro() {
        local d=$1 n
        for n in config config.worktree hooks info; do
          ro_paths+=("$d/$n")
        done
      }
      if top=$(git -C "$project_dir" rev-parse --path-format=absolute --show-toplevel 2>/dev/null); then
        gitdir=$(git -C "$project_dir" rev-parse --path-format=absolute --git-dir)
        common=$(git -C "$project_dir" rev-parse --path-format=absolute --git-common-dir)
        # Связанное дерево или подкаталог репозитория: каталог лежит вне
        # project-dir и до сих пор не был виден — открываем его так же.
        printf '%s\0' --bind "$common" "$common"
        add_gitdir_ro "$common"
        if [ "$gitdir" != "$common" ]; then
          printf '%s\0' --bind "$gitdir" "$gitdir"
          add_gitdir_ro "$gitdir"
        fi
        [ -f "$top/.git" ] && ro_paths+=("$top/.git")
        for g in "$common"/worktrees/*/gitdir; do
          [ -e "$g" ] && ro_paths+=("$g")
        done
        while IFS= read -r -d "" entry; do
          [ "''${entry%% *}" = "160000" ] || continue
          sm="$top/''${entry#*$'\t'}"
          if [ -f "$sm/.git" ]; then
            ro_paths+=("$sm/.git")
          elif [ -d "$sm/.git" ]; then
            add_gitdir_ro "$sm/.git"
          fi
        done < <(git -C "$project_dir" ls-files -z --stage)
        if [ -d "$common/modules" ]; then
          while IFS= read -r -d "" m; do
            ro_paths+=("$m")
          done < <(find "$common/modules" \( -name objects -o -name refs -o -name logs -o -name worktrees \) -prune -o \
            \( -name config -o -name config.worktree -o -name hooks -o -name info \) -print0)
        fi
        hp=$(git -C "$project_dir" config --get core.hooksPath 2>/dev/null || true)
        if [ -n "$hp" ]; then
          case "$hp" in /*) ;; *) hp="$top/$hp" ;; esac
          hp=$(realpath -m -- "$hp")
          case "$hp" in "$project_real"/*) ro_paths+=("$hp") ;; esac
        fi
      elif [ -e "$project_dir/.git" ]; then
        # Fail-closed (AI-SBX-6): `.git` есть, а git каталог не разобрал (чужой
        # владелец, повреждённый репозиторий) — без защиты не запускаем.
        echo "agents-git: $project_dir/.git есть, но git его не разобрал;" >&2
        echo "  защита метаданных (AI-SBX-7) невозможна, запуск запрещён." >&2
        return 1
      fi
      # `.envrc` — только чтение: его одобряет человек через direnv allow.
      ro_paths+=("$project_dir/.envrc")
      for p in "''${ro_paths[@]}"; do
        printf '%s\0' --ro-bind-try "$p" "$p"
      done
    }

    if [ "$cmd" = "binds" ]; then
      binds "$root" "$file"
      exit 0
    fi

    git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

    # Потолок на число игнорируемых файлов (node_modules и подобное): сверх него
    # отчёт честно говорит, что не смотрел.
    limit=20000

    # Снимок — набор секций `== имя`, строки каждой отсортированы: сравнение
    # через diff по секциям.
    snapshot() {
      local gitdir common n
      gitdir=$(git -C "$root" rev-parse --path-format=absolute --git-dir)
      common=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)
      echo "== head"
      git -C "$root" symbolic-ref -q HEAD || echo "detached"
      echo "== refs"
      git -C "$root" for-each-ref --format='%(refname) %(objectname)' | sort
      echo "== replace"
      git -C "$root" for-each-ref --format='%(refname)' refs/replace | sort
      echo "== index-flags"
      git -C "$root" ls-files -v | awk '$1 ~ /^[a-z]$/ || $1 == "S" { print }' | sort
      echo "== nested"
      find "$root" -mindepth 2 -name .git -not -path '*/.git/*' -prune -print 2>/dev/null | sort
      echo "== metadata"
      for n in hooks info config.worktree; do
        if [ -e "$common/$n" ]; then echo "$common/$n"; fi
        if [ -e "$gitdir/$n" ]; then echo "$gitdir/$n"; fi
      done | sort -u
      echo "== ignored"
      git -C "$root" ls-files -z -o -i --exclude-standard 2>/dev/null \
        | head -z -n "$limit" \
        | (cd "$root" && xargs -0 -r stat -c '%n %s %Y' 2>/dev/null) | sort || true
      if [ "$(git -C "$root" ls-files -o -i --exclude-standard 2>/dev/null | head -n "$((limit + 1))" | wc -l)" -gt "$limit" ]; then
        echo "== ignored-truncated"
      fi
    }

    section() {
      awk -v s="== $2" '$0 == s { on = 1; next } /^== / { on = 0 } on' "$1"
    }

    case "$cmd" in
      snapshot)
        snapshot > "$file"
        ;;
      report)
        [ -r "$file" ] || {
          echo "agent-launcher: отчёт git: нет снимка до сессии" >&2
          exit 0
        }
        after=$(mktemp)
        trap 'rm -f "$after"' EXIT
        snapshot > "$after"
        problems=0
        say() {
          [ "$problems" -eq 0 ] && echo "agent-launcher: отчёт git (AI-SBX-7) — проверьте:" >&2
          problems=1
          printf '  %s\n' "$1" >&2
        }

        b=$(section "$file" head)
        a=$(section "$after" head)
        [ "$a" = "$b" ] && head_same=1 || head_same=0
        [ "$head_same" -eq 1 ] || say "текущая ветка: $b → $a"

        # Ссылки: текущую ветку агент двигает штатно (коммиты) — её не считаем.
        cur="$a"
        while IFS= read -r line; do
          say "$line"
        done < <(diff <(section "$file" refs | grep -v -F "$cur " || true) \
          <(section "$after" refs | grep -v -F "$cur " || true) \
          | sed -n 's/^< \(.*\)$/ссылка изменена или удалена: \1/p; s/^> \(.*\)$/ссылка создана или сдвинута: \1/p')

        [ -n "$(section "$after" replace)" ] \
          && [ "$(section "$file" replace)" != "$(section "$after" replace)" ] \
          && say "refs/replace изменены: $(section "$after" replace | tr '\n' ' ')"

        while IFS= read -r line; do
          say "флаг индекса (скрывает правку от git status): $line"
        done < <(comm -13 <(section "$file" index-flags) <(section "$after" index-flags))

        while IFS= read -r line; do
          say "новый вложенный репозиторий: $line"
        done < <(comm -13 <(section "$file" nested) <(section "$after" nested))

        while IFS= read -r line; do
          say "появилось в метаданных git: $line"
        done < <(comm -13 <(section "$file" metadata) <(section "$after" metadata))

        # Игнорируемые: изменённые, новые и удалённые.
        while IFS= read -r line; do
          say "игнорируемый файл изменён или добавлен: ''${line% * *}"
        done < <(comm -13 <(section "$file" ignored) <(section "$after" ignored))
        if [ -n "$(section "$file" ignored-truncated)$(section "$after" ignored-truncated)" ]; then
          say "игнорируемых файлов больше $limit — проверены только первые"
        fi

        [ "$problems" -eq 0 ] && echo "agent-launcher: отчёт git: без отклонений" >&2
        exit 0
        ;;
      *) usage ;;
    esac
  '';
}
