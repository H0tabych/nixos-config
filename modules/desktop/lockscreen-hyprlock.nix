# Фича: lockscreen-hyprlock · Слот: lockscreen · Домен: desktop · Классы: N · Для: capability desktop
# Контракт: SLOT-4. Класс N, а не H (отличие от ориентировочной таблицы
# STRUCTURE.md E.2): NixOS-модуль programs.hyprlock содержит только enable/package
# и сам заводит security.pam.services.hyprlock (без PAM аутентификация падает
# в su) — без генератора конфига, в отличие от HM-модуля programs.hyprlock
# (там есть settings, ломает DOT-3). Не держит постоянного процесса — запускается
# по требованию (idle/вручную). Конфиг hyprlock — в dotfiles.
# Зависимости: —
_: {
  flake.modules.nixos.lockscreen-hyprlock = {
    programs.hyprlock.enable = true;
  };
}
