#!/usr/bin/env bash
# Смещение swap-файла для гибернации (STO-5, ROADMAP R5.1).
# Запуск: just hibernate-offset [путь-к-swap-файлу]
#
# Значение печатается, но НЕ записывается в репозиторий: my.host.resume.offset —
# факт хоста, его правит человек (ROADMAP W10). Пересчитывать при каждом
# пересоздании swap-файла — смещение привязано к физическому размещению экстентов.
#
# Почему именно `btrfs inspect-internal map-swapfile -r`, а не `filefrag`:
# man btrfs-inspect-internal(8) прямо запрещает брать physical из filefrag/FIEMAP —
# на btrfs это другое адресное пространство, а гибернации нужно смещение
# относительно блочного устройства.
set -euo pipefail

note() { echo "[hibernate-offset] $1"; }
die() {
  echo "[hibernate-offset] ОШИБКА: $1" >&2
  exit 1
}

# --- выбор файла --------------------------------------------------------
if [[ $# -ge 1 ]]; then
  swapfile="$1"
else
  # Активный файловый swap системы — источник правды: путь принадлежит фиче
  # storage/swap, дублировать его константой здесь незачем.
  mapfile -t active < <(swapon --show=NAME,TYPE --noheadings 2>/dev/null | awk '$2 == "file" { print $1 }')
  case ${#active[@]} in
    1) swapfile="${active[0]}" ;;
    0) swapfile="/swap/swapfile" ;;
    *) die "активных swap-файлов несколько (${active[*]}) — укажите нужный аргументом" ;;
  esac
fi

[[ -f $swapfile ]] || die "файл $swapfile не найден; создайте swap (фича storage/swap) и повторите"

fstype=$(stat -f -c %T "$(dirname "$swapfile")")
[[ $fstype == btrfs ]] || die "$swapfile лежит не на btrfs ($fstype) — этот способ расчёта неприменим"

# --- расчёт -------------------------------------------------------------
note "файл: $swapfile ($(stat -c %s "$swapfile") Б)"
note "нужны права root: btrfs inspect-internal map-swapfile требует их"

offset=$(sudo btrfs inspect-internal map-swapfile -r "$swapfile")
[[ $offset =~ ^[0-9]+$ ]] || die "btrfs вернул не число: $offset"

cat <<EOF

Смещение: $offset

Впишите в modules/hosts/<хост>.nix, блок my.host:

      resume.offset = $offset;

Затем примените по OPS-3: just build <хост> → nvd diff → just test <хост> → just boot <хост>.
Откат: вернуть resume.offset = null (пункт Hibernate станет недоступен, политика
крышки вернётся к обычному suspend) либо загрузиться прежним поколением.
EOF
