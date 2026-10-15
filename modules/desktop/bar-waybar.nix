# Фича: bar-waybar · Слот: bar · Домен: desktop · Классы: N · Для: capability desktop
# Контракт: SLOT-4 (демон — user-юнит на graphical-session.target). Класс N, а не H
# (отличие от ориентировочной таблицы STRUCTURE.md E.2): NixOS-модуль programs.waybar
# содержит только enable/package/systemd.target — без генератора конфига, в отличие
# от HM-модуля programs.waybar (ломает DOT-3 для приложения реестра). Конфиг — в
# dotfiles (DOT-3), cюда не входит.
# PATH юнита (DSN-S5, R6.8, исправление): юнит приходит из пакета (systemd.packages),
# без Environment=PATH — наследует минимальный PATH systemd --user менеджера
# (coreutils/findutils/grep/sed/systemd, проверено на машине 2026-10-15), в нём
# нет ни bash (custom-модули waybar/scripts/* не стартуют: "env: bash: No such
# file or directory"), ни Home-Manager профиля (rofi/mako/swayosd-client).
# %u/%h — специфайеры systemd (имя пользователя/домашний каталог), не константы
# хоста (ARCH-17).
# Зависимости: —
_: {
  flake.modules.nixos.bar-waybar = {
    programs.waybar.enable = true;
    systemd.user.services.waybar.Service.Environment = [
      "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin:%h/.local/state/nix/profile/bin:/nix/var/nix/profiles/default/bin"
    ];
  };
}
