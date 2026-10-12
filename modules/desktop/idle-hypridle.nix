# Фича: idle-hypridle · Слот: idle · Домен: desktop · Классы: N · Для: capability desktop
# Контракт: SLOT-4 (демон — user-юнит; DESK-3/DESK-4). Класс N, а не H (отличие
# от ориентировочной таблицы STRUCTURE.md E.2): NixOS-модуль services.hypridle
# содержит только enable/package и сам ставит шаблонный user-юнит на
# graphical-session.target — без генератора конфига, в отличие от HM-модуля
# services.hypridle (там есть settings, ломает DOT-3). Конфиг hypridle — в dotfiles.
# Зависимости: —
_: {
  flake.modules.nixos.idle-hypridle = {
    services.hypridle.enable = true;
  };
}
