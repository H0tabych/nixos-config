#!/usr/bin/env bash
# Проверка A16 (ARCH-14): в flake.lock один стабильный nixpkgs, не более одного
# nixpkgs-unstable, один Home Manager, а у остальных inputs nixpkgs/home-manager
# замкнуты через follows. Второй экземпляр основного канала или Home Manager —
# дефект: он удваивает замыкание и разводит overlay/allowUnfree.
# Вызывается justfile (check) и .github/workflows/check.yml.
#
# Читается flake.lock, а не `nix flake metadata --json`: результат тот же, но без
# сети и без доступа к store, поэтому проверка работает и в чистом клоне.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
note() { echo "[check-lock] $1"; }
err() {
  echo "[check-lock] ОШИБКА: $1" >&2
  fail=1
}

# Узлы lock-файла, указывающие на репозиторий nixpkgs или home-manager.
# jq нет в devshell, поэтому разбор — через nix (он есть всегда).
counts=$(nix eval --impure --raw --expr '
  let
    lock = builtins.fromJSON (builtins.readFile ./flake.lock);
    nodes = builtins.removeAttrs lock.nodes [ "root" ];
    repoOf = node: (node.locked.repo or "");
    isNixpkgs = name: node: repoOf node == "nixpkgs";
    isHm = name: node: repoOf node == "home-manager";
    namesWhere = pred: builtins.attrNames (
      builtins.listToAttrs (
        builtins.concatMap (
          n: if pred n nodes.${n} then [ { name = n; value = 1; } ] else [ ]
        ) (builtins.attrNames nodes)
      )
    );
    nixpkgsNodes = namesWhere isNixpkgs;
    hmNodes = namesWhere isHm;
  in
    builtins.concatStringsSep "\n" [
      ("nixpkgs:" + builtins.concatStringsSep "," nixpkgsNodes)
      ("home-manager:" + builtins.concatStringsSep "," hmNodes)
    ]
')

nixpkgs_nodes=$(echo "$counts" | sed -n 's/^nixpkgs://p')
hm_nodes=$(echo "$counts" | sed -n 's/^home-manager://p')

count_csv() { [ -z "$1" ] && echo 0 || (echo "$1" | tr ',' '\n' | grep -c . ); }

nixpkgs_count=$(count_csv "$nixpkgs_nodes")
hm_count=$(count_csv "$hm_nodes")

# Ожидаем ровно два узла nixpkgs: стабильный канал и nixpkgs-unstable (ARCH-14).
if [ "$nixpkgs_count" -gt 2 ]; then
  err "A16: узлов nixpkgs в lock больше двух ($nixpkgs_nodes) — у какого-то input нет follows"
else
  note "A16: узлов nixpkgs — $nixpkgs_count ($nixpkgs_nodes)"
fi

if [ "$hm_count" -gt 1 ]; then
  err "A16: Home Manager в lock больше одного раза ($hm_nodes)"
else
  note "A16: Home Manager — $hm_count ($hm_nodes)"
fi

# У каждого input, кроме nixpkgs/nixpkgs-unstable и самих flake-parts/import-tree,
# должен быть follows на nixpkgs (STR-1, таблица корня).
missing=$(nix eval --impure --raw --expr '
  let
    lock = builtins.fromJSON (builtins.readFile ./flake.lock);
    rootInputs = lock.nodes.root.inputs;
    exempt = [ "nixpkgs" "nixpkgs-unstable" "flake-parts" "import-tree" "dotfiles" ];
    nodes = lock.nodes;
    needsFollows = name:
      !(builtins.elem name exempt)
      && !(builtins.hasAttr "nixpkgs" (nodes.${rootInputs.${name}}.inputs or { }));
    bad = builtins.filter needsFollows (builtins.attrNames rootInputs);
  in builtins.concatStringsSep "," bad
')
if [ -n "$missing" ]; then
  err "A16: нет follows на nixpkgs у inputs: $missing"
else
  note "A16: follows на nixpkgs есть у всех обязанных inputs"
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
note "lock-файл соответствует A16"
