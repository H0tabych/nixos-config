# Фича: screenshot-grim · Слот: screenshot · Домен: desktop · Классы: H · Для: capability desktop
# Контракт: SLOT-4. Без постоянного процесса — скрипты (DESK-9, в dotfiles) вызывают
# grim/slurp/swappy по требованию; пункт «демон — user-юнит» не применяется.
# libnotify — скрипту hypr/scripts/screenshot нужен notify-send (уведомление
# о сохранённом файле, DSN-LAY-6); пакета не было (DSN-S5, R6.8, исправление).
# Зависимости: —
_: {
  flake.modules.homeManager.screenshot-grim =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.grim
        pkgs.slurp
        pkgs.swappy
        pkgs.libnotify
      ];
    };
}
