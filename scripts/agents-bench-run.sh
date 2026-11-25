#!/usr/bin/env bash
# Автоматический прогон набора 8.2 (R9.24, режим autonomous): задачи из TSV идут через agent-launcher
# без интерфейса, результаты и сводка — в каталоге замера. Вызывает: just agents-bench-run.
# Запускать в обычном терминале хоста, НЕ внутри песочницы агента (ключа dsh и лаунчера там нет).
#
# Проект — отдельный клон (по умолчанию публичный репозиторий из `#!project` файла задач,
# закреплённый коммитом `#!ref`): ни ваши рабочие проекты, ни их каталоги не используются; у клона
# удалён remote, отправить из него нечего.
#
# Файл задач (TSV). Строки `#!<ключ> <значение>`: project (URL или путь), ref (коммит), setup (команда
# в клоне до базового коммита), shell (префикс для baseline и проверок), baseline (команда проверки
# целого проекта). Остальные строки: id <TAB> агенты через запятую <TAB> проверка (`-` — нет) <TAB> задача.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tasks="$here/agents-bench-8.2-humanize.tsv"
out="$HOME/bench-8.2/$(date +%Y%m%d-%H%M)"
only=""
timeout_s=1800
baseline=1
project=""

usage() {
  echo "usage: agents-bench-run.sh [проект] [--tasks файл] [--out каталог] [--only id,id] [--timeout сек] [--no-baseline]" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tasks) tasks=${2:?}; shift ;;
    --out) out=${2:?}; shift ;;
    --only) only=${2:?}; shift ;;
    --timeout) timeout_s=${2:?}; shift ;;
    --no-baseline) baseline=0 ;;
    -*) usage ;;
    *) if [ -z "$project" ]; then project=$1; else usage; fi ;;
  esac
  shift
done

if [ -n "${AI_AGENT:-}" ]; then
  echo "agents-bench-run: запущен внутри песочницы агента (AI_AGENT=$AI_AGENT): откройте обычный терминал" >&2
  exit 1
fi
for cmd in agent-launcher git nix zstd timeout python3; do
  command -v "$cmd" >/dev/null || { echo "agents-bench-run: нет команды $cmd" >&2; exit 1; }
done
[ -r "$tasks" ] || { echo "agents-bench-run: нет файла задач $tasks" >&2; exit 1; }

# Директивы файла задач.
directive() { sed -n "s/^#!$1 //p" "$tasks" | head -n 1; }
[ -n "$project" ] || project=$(directive project)
ref=$(directive ref)
setup=$(directive setup)
shell_prefix=$(directive shell)
baseline_cmd=$(directive baseline)
[ -n "$project" ] || { echo "agents-bench-run: не задан проект (аргумент или #!project)" >&2; exit 1; }

mkdir -p "$out/results"
repo="$out/repo"
git clone -q --no-hardlinks "$project" "$repo"
git -C "$repo" remote remove origin
[ -z "$ref" ] || git -C "$repo" switch -q --detach "$ref"
git -C "$repo" switch -q -c bench-8.2
if [ -n "$setup" ]; then
  (cd "$repo" && bash -c "$setup")
  git -C "$repo" add -A -f
  git -C "$repo" -c user.name=bench -c user.email=bench@localhost commit -q -m "bench: setup" || true
fi
git -C "$repo" tag bench-base
echo "каталог замера: $out" >&2

# Проверки идут в окружении проекта: префикс из `#!shell` (с кавычками — через eval), затем bash -c.
run_in_env() { (cd "$repo" && eval "$shell_prefix bash -c \"\$1\""); }

if [ "$baseline" -eq 1 ] && [ -n "$baseline_cmd" ]; then
  echo "базовая проверка проекта (прогрев окружения) ..." >&2
  run_in_env "$baseline_cmd" >"$out/baseline.log" 2>&1 ||
    { echo "agents-bench-run: базовая проверка красная, см. $out/baseline.log" >&2; exit 1; }
fi

printf 'task\tagent\trc\tsecs\tverify_rc\n' >"$out/runs.tsv"

while IFS=$'\t' read -r id agents verify prompt; do
  case "$id" in '' | '#'*) continue ;; esac
  if [ -n "$only" ] && [[ ",$only," != *",$id,"* ]]; then continue; fi
  for agent in ${agents//,/ }; do
    res="$out/results/$id-$agent"
    echo "[$id/$agent] запуск ..." >&2
    git -C "$repo" reset -q --hard bench-base
    git -C "$repo" clean -fdq
    t0=$(date +%s)
    rc=0
    case "$agent" in
      # Безголовый claude не отвечает на запросы разрешений, а в его песочнице открыт $HOME
      # (--home-rw), поэтому bypassPermissions не используется: правки внутри проекта
      # (acceptEdits) и узкий список команд; чтение — штатно.
      claude)
        (cd "$repo" && timeout "$timeout_s" agent-launcher claude -- -p "$prompt" \
          --output-format json --permission-mode acceptEdits \
          --allowedTools "Bash(nix:*)" "Bash(python3:*)" "Bash(env:*)" "Bash(git diff:*)" \
          "Bash(git status:*)" "Bash(git log:*)" "Bash(git show:*)" "Bash(git grep:*)") \
          >"$res.out" 2>"$res.err" || rc=$?
        ;;
      # Текст первым аргументом — профиль headless (_agents-tools-dsh.nix).
      dsh)
        (cd "$repo" && timeout "$timeout_s" agent-launcher dsh -- "$prompt") >"$res.out" 2>"$res.err" || rc=$?
        ;;
      *) echo "agents-bench-run: неизвестный агент $agent" >&2; exit 1 ;;
    esac
    t1=$(date +%s)
    git -C "$repo" add -A
    git -C "$repo" diff --cached bench-base >"$res.diff" || true
    vrc=-
    if [ "$verify" != "-" ]; then
      vrc=0
      run_in_env "$verify" >"$res.verify" 2>&1 || vrc=$?
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$agent" "$rc" "$((t1 - t0))" "$vrc" >>"$out/runs.tsv"
    echo "[$id/$agent] код $rc, $((t1 - t0)) с, проверка $vrc" >&2
  done
done <"$tasks"

{
  for agent in claude dsh; do
    echo "## $agent"
    python3 "$here/agents-bench.py" "$agent" --project "$repo" --last 20 || true
    echo
  done
} >"$out/summary.md"
echo "готово: $out (runs.tsv, summary.md, results/)" >&2
