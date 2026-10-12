#!/usr/bin/env bash
# Первое клонирование dotfiles + проверка симлинков ~/.config (R4.6, DOT-4).
# Вызывается justfile (dotfiles-clone); url и path передаются рецептом из
# flake.lock и flake.dotfilesClonePaths, чтобы не дублировать их здесь (STR-11).
set -euo pipefail

url=$1
path=$2

if [ -e "$path" ]; then
  echo "[dotfiles-clone] $path уже существует — пропуск клонирования"
else
  git clone "$url" "$path"
fi

broken=0
while IFS= read -r -d '' link; do
  if [ ! -e "$link" ]; then
    echo "[dotfiles-clone] ОШИБКА: битый симлинк $link" >&2
    broken=1
  fi
done < <(find "$HOME/.config" -maxdepth 1 -type l -print0)

if [ "$broken" -ne 0 ]; then
  exit 1
fi

echo "[dotfiles-clone] симлинки в ~/.config рабочие"
