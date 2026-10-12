#!/usr/bin/env bash
# Проверки структуры C1, C2, C4–C12 (STRUCTURE.md, раздел 8).
# C3 — отдельно в modules/core/checks-structure.nix: нужен доступ к flake.modules.*.
# Запуск: из корня репозитория (вручную) или из песочницы nix flake check (checks.structure-shell).
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
note() { echo "[check-structure] $1"; }
err() {
  echo "[check-structure] ОШИБКА: $1" >&2
  fail=1
}

# --- C1 — STR-1: состав корня -------------------------------------------
# Игнорируемые git'ом элементы (result, .direnv, .env*, ключи) в состав корня не
# входят: STR-1 описывает содержимое репозитория, а не рабочего каталога. В
# песочнице `nix flake check` их и так нет, но при запуске вручную из рабочего
# каталога они есть — без этой проверки скрипт падал на симлинке result.
git_available=0
if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
  git_available=1
fi
is_git_ignored() {
  [ "$git_available" -eq 1 ] || return 1
  git check-ignore -q "$1" 2>/dev/null
}

allowed_root='^(flake\.nix|flake\.lock|justfile|README\.md|\.envrc|\.editorconfig|\.gitignore|\.gitleaks\.toml|\.sops\.yaml|CLAUDE\.md|\.claude|\.github|modules|machines|secrets|assets|templates|tests|scripts|docs)$'
while IFS= read -r -d '' entry; do
  name=$(basename "$entry")
  if [[ "$name" =~ $allowed_root ]]; then
    continue
  fi
  if is_git_ignored "$entry"; then
    continue
  fi
  err "C1: лишний элемент корня: $name"
done < <(find . -mindepth 1 -maxdepth 1 -not -name .git -print0)
[ "$fail" -eq 0 ] && note "C1 OK"

# --- C2 — STR-4a: глобальная уникальность имён файлов --------------------
dups=$(find modules -name '*.nix' -not -path '*/_*' -printf '%f\n' | sort | uniq -d || true)
if [ -n "$dups" ]; then
  err "C2: повтор имён файлов в modules/: $(echo "$dups" | tr '\n' ' ')"
else
  note "C2 OK"
fi

# --- C4 — STR-2: глубина ровно modules/<домен>/<файл>.nix -----------------
deep=$(find modules -mindepth 3 -name '*.nix' \
  -not -path '*/_*' \
  -not -path 'modules/hosts/*' \
  -not -path 'modules/users/*' || true)
if [ -n "$deep" ]; then
  err "C4: файлы глубже положенного: $(echo "$deep" | tr '\n' ' ')"
else
  note "C4 OK"
fi

# --- C5 — STR-4a: default.nix запрещён ------------------------------------
defaults=$(find modules -name default.nix || true)
if [ -n "$defaults" ]; then
  err "C5: найден default.nix: $(echo "$defaults" | tr '\n' ' ')"
else
  note "C5 OK"
fi

# --- C6 — STR-5: размер файла ----------------------------------------------
c6_fail=0
while IFS= read -r f; do
  lines=$(wc -l <"$f")
  if [ "$lines" -gt 250 ]; then
    err "C6: $f — $lines строк (> 250, предел STR-5)"
    c6_fail=1
  elif [ "$lines" -gt 150 ]; then
    echo "[check-structure] ПРЕДУПРЕЖДЕНИЕ C6: $f — $lines строк (> 150)"
  fi
done < <(find modules -name '*.nix')
[ "$c6_fail" -eq 0 ] && note "C6 OK"

# --- C7 — ARCH-3: config.flake.modules только в presets/hosts/base/users.nix/core
hits=$(grep -rl 'config\.flake\.modules' modules --include='*.nix' 2>/dev/null \
  | grep -v -E '^modules/(presets|hosts)/' \
  | grep -v -E '^modules/base/users\.nix$' \
  | grep -v -E '^modules/core/' \
  | grep -v -E '/_' || true)
if [ -n "$hits" ]; then
  err "C7: config.flake.modules вне разрешённых мест: $(echo "$hits" | tr '\n' ' ')"
else
  note "C7 OK"
fi

# --- C8 — STR-6: у каждой приватной части есть владелец рядом -------------
c8_fail=0
while IFS= read -r f; do
  dir=$(dirname "$f")
  base=$(basename "$f")
  # _template.nix — не приватная часть, а шаблон: HOST-1 требует его для hosts/,
  # STR-8a для users/. Владельца у него нет по определению.
  if [ "$base" = "_template.nix" ]; then
    continue
  fi
  stem=${base#_}
  stem=${stem%.nix}
  owner=""
  for cand in "$dir"/*.nix; do
    [ -e "$cand" ] || continue
    cbase=$(basename "$cand")
    case "$cbase" in _*) continue ;; esac
    cstem=${cbase%.nix}
    case "$stem" in
      "$cstem"-*)
        owner="$cbase"
        break
        ;;
    esac
  done
  if [ -z "$owner" ]; then
    err "C8: у приватной части $f не найден владелец в $dir"
    c8_fail=1
    continue
  fi
  refs=$(grep -rl "$stem" modules --include='*.nix' 2>/dev/null | grep -v -F "$dir/$owner" | grep -v -F "$f" || true)
  if [ -n "$refs" ]; then
    err "C8: приватная часть $f упомянута не только во владельце $owner: $(echo "$refs" | tr '\n' ' ')"
    c8_fail=1
  fi
done < <(find modules -name '_*.nix')
[ "$c8_fail" -eq 0 ] && note "C8 OK (или приватных частей ещё нет)"

# --- C9 — STR-10: секреты зашифрованы, значений в README нет ---------------
if [ -d secrets ]; then
  unenc=$(grep -L '^sops:' secrets/*.yaml secrets/*/*.yaml 2>/dev/null || true)
  if [ -n "$unenc" ]; then
    err "C9: не зашифрованы: $(echo "$unenc" | tr '\n' ' ')"
  else
    note "C9 OK"
  fi
else
  note "C9 OK (secrets/ ещё нет)"
fi

# --- C10 — FEAT-8, STR-7: фича+класс — ровно один пресет-владелец ---------
c10_fail=0
if [ -d modules/presets ]; then
  while IFS= read -r p; do
    bad=$(grep -nE '^\s*(home\.packages|environment\.systemPackages|services\.|systemd\.|my\.host)\s*=' "$p" || true)
    if [ -n "$bad" ]; then
      err "C10: пресет $p содержит не только imports: $(echo "$bad" | tr '\n' '; ')"
      c10_fail=1
    fi
  done < <(find modules/presets -name '*.nix')
fi
if [ -d modules/presets ] || [ -d modules/hosts ]; then
  # Составы, по которым считаем владельцев. Шаблоны (_template.nix) исключены:
  # в них состав закомментирован как пример и хостом не является — иначе каждая
  # упомянутая там фича ложно получает второго владельца.
  composition_files=$(find modules/presets modules/hosts -name '*.nix' -not -name '_*' 2>/dev/null || true)
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    file=$(find modules -mindepth 2 -maxdepth 2 -name "$name.nix" -not -path '*/_*' | head -1)
    # Ищем обращение к фиче как к модулю (n.<имя> / hm.<имя>), а не любое
    # вхождение слова — иначе опции вида my.host.users ложно совпадают с
    # фичей users (STR-9: алиасы n/hm — единственный способ сослаться на
    # config.flake.modules.<класс> в presets/hosts). n и hm — разные классы
    # одной фичи (FEAT-8: пара «фича+класс» — ровно один владелец), поэтому
    # считаем отдельно: N+H-фича законно подключается n.<имя> в одном пресете
    # и hm.<имя> в другом (например, dotfiles-link — base и user-base).
    n_count=0
    hm_count=0
    if [ -n "$composition_files" ]; then
      n_count=$(echo "$composition_files" | xargs grep -lE "\\bn\\.$name\\b" 2>/dev/null | wc -l || true)
      hm_count=$(echo "$composition_files" | xargs grep -lE "\\bhm\\.$name\\b" 2>/dev/null | wc -l || true)
    fi
    if [ "$n_count" -gt 1 ] || [ "$hm_count" -gt 1 ]; then
      err "C10: фича $name подключена более чем в одном пресете/хосте одного класса"
      c10_fail=1
    fi
    # FEAT-8: неиспользуемая фича — дефект. Проверяем по фактически объявленным
    # классам: у объявленного класса должен быть ровно один владелец, а не ноль.
    if grep -q "flake\.modules\.nixos\.$name\b" "$file" && [ "$n_count" -eq 0 ]; then
      err "C10/FEAT-8: nixos-класс фичи $name не подключён ни в один пресет или хост"
      c10_fail=1
    fi
    if grep -q "flake\.modules\.homeManager\.$name\b" "$file" && [ "$hm_count" -eq 0 ]; then
      err "C10/FEAT-8: homeManager-класс фичи $name не подключён ни в один пресет или хост"
      c10_fail=1
    fi
  done < <(find modules -mindepth 2 -maxdepth 2 -name '*.nix' \
    -not -path 'modules/core/*' -not -path 'modules/users/*' \
    -not -path 'modules/presets/*' -not -path 'modules/hosts/*' \
    -not -path '*/_*' -printf '%f\n' | sed 's/\.nix$//')
fi
[ "$c10_fail" -eq 0 ] && note "C10 OK (или composition ещё не создана)"

# --- C11 — FEAT-7: слот из метаданных есть в каталоге Архитектуры ---------
c11_fail=0
while IFS= read -r f; do
  slot=$(sed -n '1p' "$f" | grep -oE 'Слот: [^·]+' | sed -E 's/Слот: *//; s/ *$//')
  if [ -n "$slot" ] && [ "$slot" != "—" ]; then
    if ! grep -q "$slot" docs/architecture/ARCHITECTURE.md; then
      err "C11: слот '$slot' из $f не найден в каталоге ARCHITECTURE.md"
      c11_fail=1
    fi
  fi
done < <(find modules -mindepth 2 -maxdepth 2 -name '*.nix' \
  -not -path 'modules/core/*' -not -path 'modules/users/*' \
  -not -path 'modules/presets/*' -not -path 'modules/hosts/*' \
  -not -path '*/_*')
[ "$c11_fail" -eq 0 ] && note "C11 OK (или фич ещё нет)"

# --- C12 — DOT-14: нет генераторов конфигов для приложений реестра ---------
# Половина DOT-14, относящаяся к nixos-config (вторая — «нет /nix/store в
# dotfiles» — проверяется в CI самого репозитория dotfiles).
# Имена — опции NixOS/HM для приложений реестра dotfiles (A.4): nvim, zsh, foot,
# hypr*, waybar, rofi, mako, yazi, mpv, git, mangohud.
# Запрещены именно генераторы содержимого конфига (DOT-3). Разрешены и поэтому
# не перечислены: enable, package, а также programs.zsh.shellInit — им система
# сообщает ZDOTDIR, что прямо предписано DOT-12 и A.6.
registry_apps='neovim|zsh|foot|hyprland|hypridle|hyprlock|hyprpaper|waybar|rofi|mako|yazi|mpv|git|mangohud'
generator_attrs='settings|extraConfig|extraLuaConfig|initExtra|initLua|config|configFile|theme|style|plugins|profiles'
c12_hits=$(grep -rnE "(programs|services)\.($registry_apps)\.($generator_attrs)\b" modules --include='*.nix' 2>/dev/null || true)
c12_hits="$c12_hits$(grep -rnE "xdg\.configFile\.\"?($registry_apps)" modules --include='*.nix' 2>/dev/null || true)"
c12_hits="$c12_hits$(grep -rnE "home\.file\.\"\.config/($registry_apps)" modules --include='*.nix' 2>/dev/null || true)"
c12_hits=$(echo "$c12_hits" | grep -v '^$' || true)
if [ -n "$c12_hits" ]; then
  err "C12 (DOT-14): генератор конфига для приложения реестра dotfiles: $(echo "$c12_hits" | tr '\n' '; ')"
else
  note "C12 OK"
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
note "все проверки структуры пройдены"
