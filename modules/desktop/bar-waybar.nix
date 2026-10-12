# Фича: bar-waybar · Слот: bar · Домен: desktop · Классы: N · Для: capability desktop
# Контракт: SLOT-4 (демон — user-юнит на graphical-session.target). Класс N, а не H
# (отличие от ориентировочной таблицы STRUCTURE.md E.2): NixOS-модуль programs.waybar
# содержит только enable/package/systemd.target — без генератора конфига, в отличие
# от HM-модуля programs.waybar (ломает DOT-3 для приложения реестра). Конфиг — в
# dotfiles (DOT-3), cюда не входит.
# Зависимости: —
_: {
  flake.modules.nixos.bar-waybar = {
    programs.waybar.enable = true;
  };
}
