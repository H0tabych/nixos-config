# Переносимость dotfiles (A15, R9.5)

Критерий A15 (ARCHITECTURE.md): на чистой не-Nix системе `install.sh` + пакеты дистрибутива →
приложения реестра (`dotfiles/REGISTRY.md`) стартуют в пределах версионных заметок (DOT-8, DOT-10).

## Процедура

На чистой системе (ВМ или контейнер, без Nix в `PATH`), обычным пользователем:

```bash
git clone https://github.com/H0tabych/.dotfiles ~/.dotfiles && cd ~/.dotfiles
./install.sh --check-deps          # список пакетов (имена проверены на Arch Linux)
# установить пакеты менеджером дистрибутива, затем:
./install.sh                       # симлинки, заглушки machine.d, подсказка по ZDOTDIR/STARSHIP_CONFIG
./install.sh                       # повтор должен быть безвредным (идемпотентность)
export ZDOTDIR=~/.config/zsh STARSHIP_CONFIG=~/.config/starship/starship.toml   # DOT-12
checks/portability.sh              # безголовые проверки по столбцу «Проверка» реестра
checks/portability.sh --live       # + мако/swayosd/foot/eww на headless-Wayland (без сессии Hyprland)
# внутри сессии Hyprland (XDG_RUNTIME_DIR, WAYLAND_DISPLAY из неё):
checks/portability.sh --session    # hyprctl, eww bar и окно сети, мако, swayosd, foot, grim на живом композиторе
```

`checks/portability.sh` только читает; код выхода 0 — нет `FAIL`. `SKIP` печатается с причиной
(нет пакета, виртуальный GPU без 3D) и в провал не засчитывается — такие строки записываются как исключения.

## Результат 2026-11-17 (R9.5)

**Среда:** полноценная ВМ — QEMU 10.2 с KVM (`-enable-kvm -cpu host`, 4 vCPU, 4 ГБ, `virtio-vga`), официальный
cloud-образ Arch Linux (`Arch-Linux-x86_64-cloudimg.qcow2` от 2026-11-15, SHA-256 сверен с файлом зеркала; подпись
`.sig` не проверялась), ядро 7.3.4-arch1, cloud-init NoCloud (пользователь `user`, ключ SSH), актуальный `pacman -Syu`.
Вход — автологин на tty1, Hyprland запускается из `~/.bash_profile` (`exec Hyprland`); dotfiles скопированы без
`.git`, Nix нигде нет. Пакеты — по `install.sh --check-deps` + AUR (`eww-git`, `oh-my-zsh-git`, `makepkg`,
`--skippgpcheck`: источники закреплены коммитами/хэшем в PKGBUILD).

`install.sh` дважды подряд — без ошибок, идемпотентен. `checks/portability.sh --session` (внутри живой сессии
Hyprland на DRM-устройстве `virtio-vga`): **PASS 33, FAIL 0, SKIP 1**. Скриншот экрана ВМ (QMP `screendump`):
панель eww слева, окно foot с темой Glass Tide, окно сети eww, `grim` + `swappy` через `hypr/scripts/screenshot`.

| Приложение | Версия (Arch) | Проверка | Итог |
|---|---|---|---|
| neovim | 0.12.6 | `nvim --headless -c quit` (11 плагинов lazy.nvim клонируются, парсеры treesitter скачиваются) | PASS |
| zsh | 5.9.2 | `zsh -n`; интерактивный старт в pty без ошибок (oh-my-zsh из AUR) | PASS |
| starship | 1.27.0 (цель 1.25) | `starship explain` | PASS |
| foot | 1.28.0 (≥ 1.14) | `--check-config`; окно в сессии (`hyprctl clients`) | PASS |
| hypr | Hyprland 0.57.2 (≥ 0.55, Lua) | `--verify-config`; живая сессия: `hyprctl configerrors` пуст, монитор есть | PASS |
| eww | AUR `eww-git` 0.6.0 (g48f5aa8) | панель `bar` (layer `eww-bar`) и окно сети (`eww-panel`) открываются в сессии | PASS |
| mako | 1.11.0 | уведомление доходит (`notify-send` → `makoctl list`), в т. ч. от скрипта скриншота | PASS |
| swayosd | 0.3.2 | сервер работает в сессии, CSS принят | PASS |
| rofi | 2.1.1 | `-dump-config`; `-show drun` — layer `rofi` в сессии | PASS |
| yazi | 26.9.1 (в реестре 26.5.6) | старт в pty без ошибок темы | PASS |
| mpv, git, lazygit | 0.42.0, 2.56.1, 0.66.3 | конфиг читается / парсится | PASS |
| mangohud, btop, fzf, zathura | 0.8.4, 1.4.8, 0.75.0, 2026.10.23 | запуск с конфигом, `fzf --zsh` | PASS |
| `hypr/scripts/screenshot`, `net/*` | grim, slurp, swappy | снимок сохраняется, swappy открывается; `net/netstatus`, `net/tunnel health` работают без `machine.d/tunnel-env` | PASS |
| net, ai, theme | — | `bash -n`; `ai/gen/gen.py --check`; `theme/gen/gen.py --check`; DOT-1 (`scan-forbidden.sh`) | PASS |
| hyprpaper | 0.8.5 | конфиг принят (`Found 2 output(s)`); обои не рисуются: `GBM: Failed to allocate a GBM buffer` (формат AB4H) | SKIP |

### Найдено и исправлено

- `install.sh` не создавал ссылки для `zathura`, `lazygit`, `btop`, `fzf` (есть в реестре) — добавлены в `APPS`.
- `--check-deps` не перечислял пакеты этих приложений, eww-панели, hyprpaper/hyprlock, zsh-плагинов, зависимостей
  Neovim и **`grim slurp swappy`, `rfkill`** (их зовут скрипты dotfiles) — список расширен; `checks/portability.sh` проверяет
  наличие команд из скриптов.
- `hyprpaper.conf` подключает `machine.d/hypr-wallpaper.conf`, которого на не-Nix системе нет (на NixOS его пишет
  `dotfiles-link`): hyprpaper отказывался читать конфиг (DOT-5). `install.sh` создаёт файл с обоями активного варианта.
- `install.sh` печатает `ZDOTDIR` и `STARSHIP_CONFIG` (DOT-12).
- AUR-пакет `eww` 0.6.0 (коммит d87c2fd) не разбирает `:focusable "none"` — нужен eww из master (`eww-git`);
  зафиксировано в `--check-deps` и `REGISTRY.md`.

### Исключения (для R9.9)

- **hyprpaper — обои на ВМ не рисуются:** `hyprtoolkit` запрашивает буфер FP16 (`AB4H`), его не выделяет программный
  GBM (`kms_swrast` на `virtio-vga` без 3D; QEMU из nixpkgs собран без GL-дисплея). Конфиг и путь к обоям разобраны.
  На реальном GPU проверено на машине (R6.8). Закрыть можно ВМ с virgl или вручную на железе; hyprlock тем же путём не проверялся.
- Не проверено вживую: содержимое виджетов eww, зависящее от железа (батарея, Wi-Fi, Bluetooth, громкость — в ВМ их нет),
  визуальная часть mpv/zathura/btop/MangoHud, Telegram-тема.
- Версии новее заметок реестра (yazi 26.9.1 против 26.5.6, starship 1.27 против 1.25) — конфиги принимаются.

### Повтор

Харнесс (без KVM-прав у пользователя не поднимется): `qemu-system-x86_64` из `nix shell nixpkgs#qemu_test`
(`qemu_kvm` из кэша в агентской среде не запускался: несовместимость glibc), диск — qcow2-оверлей на cloud-образ,
`-smbios type=1,serial=ds=nocloud;s=http://10.0.2.2:8000/` и каталог с `user-data`/`meta-data` за `python3 -m http.server`,
проброс `-nic user,hostfwd=tcp:127.0.0.1:2222-:22`, `-vga none -device virtio-vga -display none`, снимок экрана —
QMP `screendump`. Дальше — процедура выше; пакеты — по `install.sh --check-deps`; для автозапуска сессии — автологин
getty на tty1 и `exec Hyprland` в `~/.bash_profile`. Процессы сессии (`mako`, `swayosd-server`, `eww`, `hyprpaper`) на
NixOS запускают systemd-юниты (`my.*`-фичи), на других системах их запускает пользователь — в `hyprland.lua` автозапуска нет.
