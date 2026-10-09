# Единая точка входа для людей и CI (STRUCTURE.md, раздел 5.4)
# Рецепты — только оболочки над nix/sops/nvd/scripts (STR, раздел 2).

set shell := ["bash", "-euo", "pipefail", "-c"]

fmt:
    nix fmt

check: fmt
    nix flake check

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

# TODO(DOT-4, Этап 4): первое клонирование dotfiles ещё не специфицировано
dotfiles-clone:
    @echo "dotfiles-clone: см. docs/architecture/ARCHITECTURE.md DOT-4 — ещё не реализовано"
    @exit 1

add-host name:
    scripts/new-feature.sh host {{ name }}

add-user name:
    scripts/new-feature.sh user {{ name }}

new-feature domain name:
    scripts/new-feature.sh {{ domain }} {{ name }}

hibernate-offset:
    scripts/hibernate-offset.sh

sops-edit file:
    sops {{ file }}

sops-rekey:
    sops updatekeys secrets/*.yaml
