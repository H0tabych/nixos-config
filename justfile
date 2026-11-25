# Единая точка входа для людей и CI (STRUCTURE.md, раздел 5.4)
# Рецепты — только оболочки над nix/sops/nvd/scripts (STR, раздел 2).

set shell := ["bash", "-euo", "pipefail", "-c"]

fmt:
    nix fmt

# OPS-2 требует в CI именно *проверку* форматирования. `nix fmt` правит файлы, и
# когда check зависел от fmt, CI уже не мог упасть на формате: treefmt-check
# внутри `nix flake check` видел исправленное. Поэтому здесь --ci (treefmt:
# --no-cache --fail-on-change), а правит файлы отдельный рецепт fmt.
check:
    nix fmt -- --ci
    nix flake check
    bash scripts/check-lock.sh

# OPS-2, A2: каждый хост вычисляется до пути derivation, без сборки (тяжёлые
# unfree-пакеты в CI не собираются). Полная сборка — только у хоста класса vm
# (build-vm.yml); остальные хосты собираются на машине (OPS-3).
eval-hosts:
    #!/usr/bin/env bash
    set -euo pipefail
    hosts=$(nix eval --json .#nixosConfigurations --apply builtins.attrNames | tr -d '[]"' | tr ',' ' ')
    for h in $hosts; do
        echo "eval $h"
        nix eval --raw ".#nixosConfigurations.$h.config.system.build.toplevel.drvPath" >/dev/null
    done

# TODO(R2.9/18.9): разметка диска и установка ещё не специфицированы пошагово (Этап 2)
bootstrap host:
    @echo "bootstrap {{ host }}: см. docs/architecture/ARCHITECTURE.md §18.9 и ROADMAP R2.9 — ещё не реализовано"
    @exit 1

build host:
    nixos-rebuild build --flake .#{{ host }}

test host:
    sudo nixos-rebuild test --flake .#{{ host }}

boot host:
    sudo nixos-rebuild boot --flake .#{{ host }}

vm host:
    nixos-rebuild build-vm --flake .#{{ host }}

update input="":
    if [ -n "{{ input }}" ]; then nix flake update {{ input }}; else nix flake update; fi
    nixos-rebuild build --flake .#$(hostname)
    nvd diff /run/current-system result

# R4.6 (DOT-4): первое клонирование dotfiles для текущего пользователя.
dotfiles-clone:
    scripts/dotfiles-clone.sh \
        "$(nix eval --impure --raw --expr 'let l = builtins.fromJSON (builtins.readFile ./flake.lock); o = l.nodes.dotfiles.original; in "https://github.com/${o.owner}/${o.repo}.git"')" \
        "$(nix eval --raw .#dotfilesClonePaths.$(whoami))"

# Заготовка фичи из modules/_templates/feature.nix (чек-лист 18.1). Пресет и
# каталог слотов правит человек: до подключения в пресет C10 (FEAT-8) красный.
new-feature domain name *audience="":
    bash scripts/new-feature.sh {{ domain }} {{ name }} {{ audience }}

# add-host и add-user (правки .sops.yaml, ключи, my.host.users) не реализованы:
# шаблоны копируются вручную по чек-листам 18.3 и 18.4.
add-host name:
    @echo "add-host {{ name }}: не реализован."
    @echo "Скопируйте modules/hosts/_template.nix → modules/hosts/{{ name }}.nix по чек-листу 18.3."
    @exit 1

add-user name:
    @echo "add-user {{ name }}: не реализован."
    @echo "Скопируйте modules/users/_template.nix → modules/users/{{ name }}.nix по чек-листу 18.4."
    @exit 1

# Смещение swap-файла для my.host.resume.offset (STO-5). Значение печатается,
# в репозиторий его вписывает человек (W10). Аргумент — путь к файлу, если
# автоопределение по `swapon --show` не подходит.
hibernate-offset file="":
    bash scripts/hibernate-offset.sh {{ file }}

# Замер отклика промпта starship (DSN-A13, ROADMAP R6.4/R6.9, DESIGN_SYSTEM.md
# Приложение I.7). Каталоги — реальные рабочие репозитории и самый большой из них.
bench-prompt config *dirs:
    python3 scripts/bench-prompt.py --config {{ config }} {{ dirs }}

# Сводка по сессиям агентов для замера набора 8.2 (AI_SUBSYSTEM 8.2/8.3, R9.24): время,
# ходы, инструменты, токены. Только читает журналы сессий; агент — claude или dsh.
agents-bench agent *args:
    python3 scripts/agents-bench.py {{ agent }} {{ args }}

# Прогон набора 8.2 через agent-launcher без интерфейса (R9.24, режим autonomous): отдельный клон
# публичного проекта из scripts/agents-bench-8.2-humanize.tsv, сводка в ~/bench-8.2/<дата>/.
# Запускать в обычном терминале хоста, не внутри песочницы агента. Опции: --only 3,4 --timeout <с>.
agents-bench-run *args:
    bash scripts/agents-bench-run.sh {{ args }}

# SEC-9: pre-commit сканер секретов. Однократно на клон; devshell этого не делает
# (AI-SBX-7: shellHook, переписывавший core.hooksPath, обходил защиту метаданных git).
hooks:
    git config core.hooksPath scripts/git-hooks

sops-edit file:
    sops {{ file }}

sops-rekey:
    sops updatekeys secrets/*.yaml
