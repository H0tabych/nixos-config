#!/usr/bin/env python3
"""Сводка по сессиям агентов для замера набора 8.2: время, ходы, вызовы инструментов, токены.
Вызывает: just agents-bench (AI_SUBSYSTEM 8.2/8.3, ROADMAP R9.24). Только читает журналы сессий.

  just agents-bench claude              # последние 8 сессий claude для текущего каталога
  just agents-bench dsh --last 16 --project ~/Documents/my_projects/hh_parser
  just agents-bench claude --file <путь/к/сессии.jsonl>

Вывод — таблица Markdown для вставки в docs/runbook/ai.md §5 (журнал замера 8.2).
Время: у dsh — сумма интервалов turn/start…turn/end (без ожидания пользователя); у claude —
первая…последняя запись журнала (включает паузы между репликами, поэтому на замере вести
сессию без пауз: одна задача — один запуск). Токены: вход без кэша / чтение кэша / запись кэша /
выход; у claude — по одному учёту на сообщение (`message.id`), подагенты (sidechain) не входят.
"""
import argparse, json, os, subprocess, sys
from datetime import datetime
from typing import Any


def read_dsh(path):
    out = subprocess.run(["zstd", "-dc", path], capture_output=True, check=True).stdout
    s: dict[str, Any] = dict(title="", secs=0.0, turns=0, tools=0, inp=0, cache_r=0, cache_w=0, out=0, errors=0)
    t0 = None
    for raw in out.splitlines():
        o = json.loads(raw)
        t, d = o.get("type"), o.get("data", {})
        if t == "turn/start":
            t0 = o["time"]
        elif t == "turn/end":
            s["turns"] += 1
            if t0 is not None:
                s["secs"] += (o["time"] - t0) / 1000
                t0 = None
            if d.get("reason", {}).get("kind") not in ("completed", None):
                s["errors"] += 1
        elif t == "tool/call":
            s["tools"] += 1
        elif t == "assistant/message":
            u = d.get("usage") or {}
            s["inp"] += u.get("inputTokens", 0)
            s["cache_r"] += u.get("cacheReadTokens", 0)
            s["cache_w"] += u.get("cacheWriteTokens", 0)
            s["out"] += u.get("outputTokens", 0)
        elif t == "user/message" and not s["title"]:
            s["title"] = "".join(c.get("text", "") for c in d.get("content", []) if c.get("type") == "text")
    return s


def read_claude(path):
    s: dict[str, Any] = dict(title="", secs=0.0, turns=0, tools=0, inp=0, cache_r=0, cache_w=0, out=0, errors=0)
    usage, first, last = {}, None, None
    for raw in open(path, encoding="utf-8"):
        o = json.loads(raw)
        ts = o.get("timestamp")
        if ts:
            ts = datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
            first = ts if first is None else first
            last = ts
        if o.get("isSidechain"):
            continue
        m = o.get("message") or {}
        if o.get("type") == "user" and isinstance(m.get("content"), str) and not o.get("isMeta"):
            if m["content"].startswith("<"):  # служебные записи (/clear и т. п.), не запрос
                continue
            s["turns"] += 1
            s["title"] = s["title"] or m["content"]
        elif o.get("type") == "assistant":
            for c in m.get("content", []):
                if c.get("type") == "tool_use":
                    s["tools"] += 1
            if m.get("usage"):
                usage[m.get("id")] = m["usage"]  # одно сообщение пишется по блокам: берём последний учёт
    for u in usage.values():
        s["inp"] += u.get("input_tokens", 0)
        s["cache_r"] += u.get("cache_read_input_tokens", 0)
        s["cache_w"] += u.get("cache_creation_input_tokens", 0)
        s["out"] += u.get("output_tokens", 0)
    s["secs"] = (last - first) if first is not None and last is not None else 0.0
    return s


def session_files(agent, project):
    key = os.path.abspath(os.path.expanduser(project))
    if agent == "claude":
        d = os.path.expanduser("~/.claude/projects/" + key.replace("/", "-").replace("_", "-").replace(".", "-"))
        return sorted((os.path.join(d, f) for f in os.listdir(d) if f.endswith(".jsonl")), key=os.path.getmtime) if os.path.isdir(d) else []
    root = os.path.expanduser("~/.local/state/agents/dsh/dsh-home/sessions")
    d = os.path.join(root, "-" + key.replace("/", "-") + "--")  # имя каталога: путь, «/» → «-», в рамке «-…--»
    if not os.path.isdir(d):
        return []
    files = [os.path.join(d, x, "session.v4.jsonl.zstd") for x in os.listdir(d)]
    return sorted((f for f in files if os.path.isfile(f)), key=os.path.getmtime)


ap = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
ap.add_argument("agent", choices=["claude", "dsh"])
ap.add_argument("--project", default=os.getcwd(), help="каталог проекта (по умолчанию текущий)")
ap.add_argument("--last", type=int, default=8, help="сколько последних сессий показать")
ap.add_argument("--file", action="append", default=[], help="конкретный файл сессии (можно несколько раз)")
a = ap.parse_args()

files = a.file or session_files(a.agent, a.project)[-a.last:]
if not files:
    sys.exit(f"нет сессий {a.agent} для {a.project}")
read = read_dsh if a.agent == "dsh" else read_claude
print("| Сессия | Задача (начало запроса) | Время, с | Ходов | Инструментов | Вход | Кэш, чтение | Кэш, запись | Выход |")
print("|---|---|---|---|---|---|---|---|---|")
for f in files:
    s = read(f)
    sid = os.path.basename(os.path.dirname(f) if a.agent == "dsh" else f).replace("session-", "").replace(".jsonl", "")[:8]
    title = " ".join(s["title"].split())[:48].replace("|", "/")
    print(f"| {sid} | {title} | {s['secs']:.0f} | {s['turns']} | {s['tools']} | {s['inp']} | {s['cache_r']} | {s['cache_w']} | {s['out']} |")
