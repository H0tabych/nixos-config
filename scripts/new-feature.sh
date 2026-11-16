#!/usr/bin/env bash
# Создаёт файл фичи modules/<домен>/<имя>.nix из modules/_templates/feature.nix (STR-5, 18.1).
# Вызывает justfile (new-feature <домен> <имя> [для кого]); пресет и каталог не правит.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  echo "использование: scripts/new-feature.sh <домен> <имя-фичи> [для кого]" >&2
  exit 2
}
die() {
  echo "[new-feature] ОШИБКА: $1" >&2
  exit 1
}

[ "$#" -ge 2 ] && [ "$#" -le 3 ] || usage
domain=$1
name=$2
audience=${3:-—}

# Фичи живут только в каталогах-доменах (STR-2); core, users, hosts, presets и
# приватные `_*` — не домены фич (STR-8, STR-7).
case "$domain" in
  core | users | hosts | presets | _* | */* | '') die "«$domain» — не домен фич" ;;
esac
[ -d "modules/$domain" ] || die "каталога modules/$domain нет (новый домен — решение по STR-3, не скриптом)"

# Имя файла = имя фичи = ключ flake.modules.<класс>.<имя>; дефисы допустимы (STR-4).
[[ "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || die "имя «$name»: строчные латинские буквы, цифры и дефис"

# C2 (STR-4a): имя файла уникально во всём modules/, включая хосты и пресеты.
clash=$(find modules -name "$name.nix" -not -path '*/_templates/*' | head -1)
[ -z "$clash" ] || die "имя занято: $clash (STR-4a)"

template=modules/_templates/feature.nix
[ -f "$template" ] || die "нет шаблона $template"
target=modules/$domain/$name.nix

# Шапка шаблона («Шаблон фичи…») отбрасывается: метаданные STR-5 должны быть
# первой строкой файла (их читает C3 в modules/core/checks-structure.nix).
sed -n '/^# Фича:/,$p' "$template" |
  sed \
    -e "s|<имя-файла>|$name|" \
    -e 's|<слот или "—">|—|' \
    -e "s|<домен>|$domain|" \
    -e 's|<nixos\|homeManager>|nixos|' \
    -e "s|<кто>|$audience|" \
    -e "s|CHANGE_ME|$name|g" >"$target"

echo "[new-feature] создан $target"
cat <<EOF
Дальше (чек-лист 18.1 Архитектуры):
  1. Заполните метаданные первой строки (слот, классы, адресат) и контракт; конфиги
     приложений — в dotfiles (DOT-3), не здесь.
  2. Подключите фичу ровно в одном пресете или хосте (FEAT-8): n.$name в
     modules/presets/<пресет>.nix. Пока этого нет, C10 в nix flake check красный.
  3. Слот — добавьте строку в каталог ARCHITECTURE.md, раздел 6 (FEAT-7, C11).
  4. nix fmt && nix flake check; соберите затронутые хосты.
EOF
