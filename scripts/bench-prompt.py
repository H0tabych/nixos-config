#!/usr/bin/env python3
"""Замер отклика промпта starship: медиана, p95 и максимум в мс (левая и правая части).
Запуск: just bench-prompt <конфиг> <каталог>... (DSN-S1, ROADMAP R6.4, DESIGN_SYSTEM.md Приложение I.7)
"""
import argparse, os, statistics, subprocess, sys, time

def run(cmd, env, cwd):
    t = time.perf_counter()
    subprocess.run(cmd, env=env, cwd=cwd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return (time.perf_counter() - t) * 1000

def stats(xs):
    xs = sorted(xs)
    return statistics.median(xs), xs[round(0.95 * (len(xs) - 1))], xs[-1]

ap = argparse.ArgumentParser()
ap.add_argument("--runs", type=int, default=100)
ap.add_argument("--config", required=True)
ap.add_argument("dirs", nargs="+")
a = ap.parse_args()
cfg = os.path.abspath(a.config)
if not os.path.isfile(cfg):
    sys.exit(f"нет файла конфига: {cfg}")
env = dict(os.environ, STARSHIP_SHELL="zsh", STARSHIP_SESSION_KEY="bench", STARSHIP_CONFIG=cfg)
args = ["--status=0", "--jobs=0", "--cmd-duration=0", "--terminal-width=120"]
left, right = ["starship", "prompt", *args], ["starship", "prompt", "--right", *args]
base = stats([run(["true"], env, "/") for _ in range(a.runs)])
print(f"fork+exec пустой программы: медиана {base[0]:.1f} мс")
print(f"{'каталог':<28}{'медиана':>9}{'p95':>8}{'макс':>8}   (левая + правая, мс)")
for d in map(os.path.abspath, a.dirs):
    xs = [run(left, env, d) + run(right, env, d) for _ in range(a.runs + 10)][10:]
    m, p, x = stats(xs)
    print(f"{os.path.basename(d) or d:<28}{m:9.1f}{p:8.1f}{x:8.1f}")
