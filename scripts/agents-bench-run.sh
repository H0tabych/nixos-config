#!/usr/bin/env bash
# Автоматический прогон набора 8.2 (R9.24, режим autonomous): задачи из TSV идут через agent-launcher
# без интерфейса, результаты и сводка — в каталоге замера. Вызывает: just agents-bench-run <проект>.
# Запускать в обычном терминале хоста, НЕ внутри песочницы агента (ключа dsh и лаунчера там нет).
#
# Формат TSV (табуляции): id <TAB> агенты через запятую (claude,dsh) <TAB> проверка (`-` — нет) <TAB> задача.
# Проверка — команда в `nix develop` клона после запуска (код возврата пишется в runs.tsv).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tasks="$here/agents-bench-8.2-dof.tsv"
out="$HOME/bench-8.2/$(date +%Y%m%d-%H%M)"
only=""
timeout_s=1800
baseline=1
project=""

usage() {
  echo "usage: agents-bench-run.sh <проект> [--tasks файл] [--out каталог] [--only id,id] [--timeout сек] [--no-baseline]" >&2
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
    *) [ -z "$project" ] && project=$1 || usage ;;
  esac
  shift
done
[ -n "$project" ] || usage

if [ -n "${AI_AGENT:-}" ]; then
  echo "agents-bench-run: запущен внутри песочницы агента (AI_AGENT=$AI_AGENT): откройте обычный терминал" >&2
  exit 1
fi
for cmd in agent-launcher git nix zstd timeout python3; do
  command -v "$cmd" >/dev/null || { echo "agents-bench-run: нет команды $cmd" >&2; exit 1; }
done
[ -r "$tasks" ] || { echo "agents-bench-run: нет файла задач $tasks" >&2; exit 1; }
project=$(cd "$project" && git rev-parse --show-toplevel)
[ -z "$(git -C "$project" status --porcelain)" ] ||
  echo "agents-bench-run: в $project есть неотправленные правки — клон их не увидит (берётся последний коммит)" >&2

mkdir -p "$out/results"
repo="$out/repo"
git clone -q --no-hardlinks "$project" "$repo"
git -C "$repo" switch -q -c bench-8.2
git -C "$repo" tag bench-base
echo "каталог замера: $out" >&2

if [ "$baseline" -eq 1 ]; then
  echo "базовая проверка (just test) — прогревает кэш сборки ..." >&2
  (cd "$repo" && nix develop --command just test) >"$out/baseline.log" 2>&1 ||
    { echo "agents-bench-run: базовые тесты красные, см. $out/baseline.log" >&2; exit 1; }
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
      # bypassPermissions: безголовый запуск не может отвечать на запросы, а dsh в autonomous их
      # и не задаёт (danger-full-access); границу даёт песочница лаунчера.
      claude)
        (cd "$repo" && timeout "$timeout_s" agent-launcher claude -- -p "$prompt" \
          --output-format json --permission-mode bypassPermissions) >"$res.out" 2>"$res.err" || rc=$?
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
      (cd "$repo" && nix develop --command bash -c "$verify") >"$res.verify" 2>&1 || vrc=$?
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
