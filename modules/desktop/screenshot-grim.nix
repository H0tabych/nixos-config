# Фича: screenshot-grim · Слот: screenshot · Домен: desktop · Классы: H · Для: capability desktop
# Контракт: SLOT-4. Без постоянного процесса — скрипты (DESK-9, в dotfiles) вызывают
# grim/slurp/swappy по требованию; пункт «демон — user-юнит» не применяется.
# Зависимости: —
_: {
  flake.modules.homeManager.screenshot-grim =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.grim
        pkgs.slurp
        pkgs.swappy
      ];
    };
}
