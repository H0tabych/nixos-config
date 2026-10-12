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

# TODO(R9.2): scripts/new-feature.sh ещё не создан. До тех пор шаблоны
# копируются вручную: modules/_templates/feature.nix, modules/_templates/preset.nix,
# modules/hosts/_template.nix, modules/users/_template.nix (чек-листы 18.1, 18.3, 18.4).
add-host name:
    @echo "add-host {{ name }}: scripts/new-feature.sh не реализован (ROADMAP R9.2)."
    @echo "Скопируйте modules/hosts/_template.nix → modules/hosts/{{ name }}.nix по чек-листу 18.3."
    @exit 1

add-user name:
    @echo "add-user {{ name }}: scripts/new-feature.sh не реализован (ROADMAP R9.2)."
    @echo "Скопируйте modules/users/_template.nix → modules/users/{{ name }}.nix по чек-листу 18.4."
    @exit 1

new-feature domain name:
    @echo "new-feature {{ domain }} {{ name }}: scripts/new-feature.sh не реализован (ROADMAP R9.2)."
    @echo "Скопируйте modules/_templates/feature.nix → modules/{{ domain }}/{{ name }}.nix по чек-листу 18.1."
    @exit 1

# TODO(R5.1): scripts/hibernate-offset.sh появится вместе с фичей storage/swap —
# смещение считается по уже созданному swap-файлу (STO-5).
hibernate-offset:
    @echo "hibernate-offset: scripts/hibernate-offset.sh не реализован (ROADMAP R5.1, STO-5)"
    @exit 1

sops-edit file:
    sops {{ file }}

sops-rekey:
    sops updatekeys secrets/*.yaml
