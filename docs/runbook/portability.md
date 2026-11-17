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
checks/portability.sh --live       # + старт мако/swayosd/foot/hyprpaper/eww на headless-Wayland
```

`checks/portability.sh` только читает; код выхода 0 — нет `FAIL`. `SKIP` печатается с причиной
(нет пакета, нет GPU/DRM) и в провал не засчитывается — такие строки записываются как исключения.

## Результат 2026-11-17 (R9.5)

Среда: Arch Linux (bootstrap 2026.11.01, пакеты из зеркала на день прогона), **безрутовый контейнер**
`bwrap` с пространством имён пользователя — на машине нет `/dev/kvm` и `/dev/dri`, а `sudo`/демон
контейнеров агенту запрещены. Внутри — обычный пользователь uid 1000, `PATH` без `/nix`, пустой `HOME`,
dotfiles смонтированы только на чтение, настоящий `pacman`. Это не полноценная ВМ: нет systemd, GPU и
реального дисплея (см. «Исключения»).

`install.sh` дважды подряд — без ошибок; `--check-deps` — без побочных эффектов. `checks/portability.sh --live`:
**PASS 25, FAIL 0, SKIP 4** (eww дважды: в статических проверках и в live).

| Приложение | Версия (Arch) | Проверка | Итог |
|---|---|---|---|
| neovim | 0.12.6 | `nvim --headless -c quit` (плагины lazy.nvim клонируются: 11 штук; парсеры treesitter скачиваются) | PASS |
| zsh | 5.9.2 | `zsh -n`, интерактивный старт в pty без вывода ошибок | PASS |
| starship | 1.27.0 (цель 1.25) | `starship explain` | PASS |
| foot | 1.28.0 (≥ 1.14) | `foot --check-config`; живой старт на headless-sway | PASS |
| hypr | Hyprland 0.57.2 (≥ 0.55, Lua) | `Hyprland --verify-config` на `hyprland.lua` → `config ok` | PASS (живой старт — SKIP) |
| rofi | 2.1.1 | `rofi -dump-config` | PASS |
| mako | 1.11.0 | живой старт на headless-sway | PASS |
| swayosd | 0.3.2 | живой старт (CSS принят) | PASS |
| yazi | 26.9.1 (в реестре 26.5.6) | `--version`, старт в pty без ошибок темы | PASS |
| mpv | 0.42.0 | `--list-options` с конфигом | PASS |
| git, lazygit | 2.56.1, 0.66.3 | конфиг читается / парсится | PASS |
| mangohud, btop, fzf, zathura | 0.8.4, 1.4.8, 0.75.0, 2026.10.23 | запуск с конфигом, `fzf --zsh` | PASS |
| net, ai, theme | — | `bash -n`; `ai/gen/gen.py --check`; `theme/gen/gen.py --check`; DOT-1 (`scan-forbidden.sh`) | PASS |

### Найдено и исправлено

- `install.sh` не создавал ссылки для `zathura`, `lazygit`, `btop`, `fzf` (есть в реестре) — добавлены в `APPS`.
- `--check-deps` не перечислял пакеты этих приложений, eww-панели, hyprpaper/hyprlock, zsh-плагинов и
  зависимостей Neovim — список расширен.
- `hyprpaper.conf` подключает `machine.d/hypr-wallpaper.conf`, которого на не-Nix системе нет (на NixOS его пишет
  `dotfiles-link`): hyprpaper отказывался читать конфиг (нарушение DOT-5). `install.sh` теперь создаёт файл
  с обоями активного варианта палитры тем же содержимым.
- `install.sh` печатает значения `ZDOTDIR` и `STARSHIP_CONFIG` (DOT-12), которые на других системах задаёт пользователь.

### Исключения (записаны для R9.9)

- **eww** — пакета нет в официальных репозиториях Arch (AUR/сборка из исходников); сборка не выполнялась
  (стороннее ПО из сети без согласия владельца). Проверены только его сценарии (`bash -n`).
  **Не проверено**: старт `eww`, виджеты панели и окна сети.
- **Hyprland вживую и hyprpaper** — в окружении нет GPU/DRM (`CBackend::create() failed`); hyprpaper требует
  протоколов Hyprland, которых нет у запасного носителя (headless-sway, на нём проверены мako, swayosd, foot).
  Конфиг Hyprland проверен `--verify-config`. Нужна ВМ с виртуальным GPU или реальная сессия.
- **oh-my-zsh** — в официальных репозиториях Arch нет; `.zshrc` стартует без него без ошибок (запасные пути,
  деградация без плагинов), версионная заметка реестра это допускает.
- Приложения без безголовой проверки (визуальный вид — mpv OSD, zathura, btop, MangoHud-оверлей; Telegram-тема)
  проверены только на запуск с конфигом.
- Версии новее заметок реестра (yazi 26.9.1 против 26.5.6, starship 1.27 против 1.25) — конфиги принимаются;
  заметки не менялись.

### Повтор в ВМ

Для полной приёмки A15 прогнать процедуру выше в ВМ с графикой (Arch или Fedora) и с `--live` на Hyprland;
вывод `checks/portability.sh --live` приложить сюда. Харнесс без KVM, использованный 2026-11-17: распаковать
`archlinux-bootstrap-x86_64.tar.zst` (проверить `sha256sums.txt` с зеркала) в каталог, запускать
`bwrap --unshare-user --uid 1000 --gid 1000 --unshare-pid --ro-bind <rootfs> / --dev /dev --proc /proc
--tmpfs /tmp --tmpfs /run --bind <home> /home/user --ro-bind ~/.dotfiles /dotfiles …`; пакеты ставить отдельным
запуском с `uid 0` (`DisableSandbox` в `pacman.conf`, `pacman-key --init`).
