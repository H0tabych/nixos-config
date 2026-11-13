#!/usr/bin/env bash
# Опыт R9.21 (AI-SBX-13, AI-A20): видит ли Claude из песочницы лаунчера супервизор
# фоновых сессий и переживает ли фоновая сессия закрытие запуска. Запускает пользователь
# на машине; скрипт ничего не удаляет и не меняет настройки, печатает наблюдения.
# Нужен `agent-launcher` в PATH; claude хоста берётся из него (или CLAUDE_HOST_BIN).
# Результат (весь вывод) — в AI_SUBSYSTEM.md, AI-SBX-13/AI-A20, и решение владельца.
set -u

uid=$(id -u)
step() { printf '\n=== %s\n' "$*"; }
run() {
  printf '$ %s\n' "$*"
  "$@" 2>&1 | sed 's/^/    /'
  printf '    rc=%s\n' "${PIPESTATUS[0]}"
}

command -v agent-launcher > /dev/null || { echo "нет agent-launcher в PATH" >&2; exit 1; }
# Голого `claude` в PATH нет (AI-AGT-4) — берём бинарник из самого лаунчера: тот же пакет,
# но запускаем его вне песочницы (взгляд хоста). Можно задать явно: CLAUDE_HOST_BIN=<путь>.
host_claude=${CLAUDE_HOST_BIN:-$(grep -o -m1 '/nix/store/[^ "]*/bin/claude' "$(readlink -f "$(command -v agent-launcher)")")}
[ -x "$host_claude" ] || { echo "не нашёл бинарник claude в agent-launcher; задайте CLAUDE_HOST_BIN" >&2; exit 1; }
echo "claude хоста: $host_claude"

# Проект опыта — каталог репозитория, уже подтверждённый в Claude (иначе --bg отвечает
# «Workspace not trusted»): по умолчанию текущий каталог, либо PROBE_DIR=<путь>.
work=${PROBE_DIR:-$PWD}
cd "$work" || exit 1

step "1. Хост: супервизор и его сокеты (до опыта)"
run "$host_claude" daemon status
run ls -la "/tmp/cc-daemon-$uid" "/run/user/$uid/cc-socks"

step "2. Песочница: видит ли клиент супервизора хоста (ожидание: нет — свой /tmp, свой pid)"
run agent-launcher claude -- daemon status
run agent-launcher claude -- agents

step "3. Песочница: фоновая сессия (запуск с --bg) и что с ней после выхода из запуска"
bg_out=$(agent-launcher claude -- --bg "Ответь одним словом: ok" 2>&1)
printf '%s\n' "$bg_out" | sed 's/^/    /'
sid=$(printf '%s\n' "$bg_out" | grep -o -m1 'backgrounded · [0-9a-f]*' | awk '{print $3}')
echo "-- id сессии: ${sid:-<не определён>}"
sleep 5

step "4. ГЛАВНОЕ: где исполняется воркер — в песочнице или на хосте (пространства имён)"
echo "-- свой mount-namespace (хост):   $(readlink /proc/self/ns/mnt)"
echo "-- свой pid-namespace (хост):     $(readlink /proc/self/ns/pid)"
python3 -I - << 'PY'
import json, os
home = os.path.expanduser("~")
try:
    d = json.load(open(f"{home}/.claude/daemon/roster.json"))
except Exception as e:
    print("   roster.json не прочитан:", e); raise SystemExit
print("   супервизор из roster.json: pid", d.get("supervisorPid"))
for sid, w in d.get("workers", {}).items():
    pid = w.get("pid")
    def ns(kind):
        try: return os.readlink(f"/proc/{pid}/ns/{kind}")
        except Exception as e: return f"<недоступно: {e.__class__.__name__}>"
    print(f"   воркер {sid}: pid {pid} cwd {w.get('cwd')}")
    print(f"      mnt: {ns('mnt')}   pid: {ns('pid')}")
    try:
        cmd = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ")[:160].decode(errors="replace")
        print("      cmdline:", cmd)
    except Exception as e:
        print("      cmdline недоступен:", e.__class__.__name__)
PY
echo "   (mnt воркера = свой mnt выше → воркер ВНЕ песочницы; иное → в отдельном пространстве)"
echo "-- процессы воркеров и их родители:"
ps -eo pid,ppid,args | grep -E 'bg-spare|bg-pty-host|daemon run' | grep -v grep | cut -c1-170 | sed 's/^/    /'

step "5. Хост: статус и доступность сессии из нового запуска"
run "$host_claude" daemon status
run "$host_claude" agents --json
if [ -n "${sid:-}" ]; then
  echo "-- из нового запуска в песочнице (подкоманды теперь идут первым словом):"
  run agent-launcher claude -- logs "$sid"
fi

step "Итог для записи"
cat << EOF
Каталог опыта: $work.
Сессию опыта убрать: \`$host_claude stop <id>\`, затем \`$host_claude rm <id>\` (id напечатан выше).
Запишите: (а) видна ли сессия из хоста и из нового запуска, (б) жив ли супервизор,
(в) где лежат его сокеты (шаг 1 хоста против шага 2). От этого зависит выбор:
долгоживущая песочница с общим каталогом сокетов либо записанное ограничение (AI-A20).
EOF
