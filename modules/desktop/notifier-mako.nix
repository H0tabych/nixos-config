# Фича: notifier-mako · Слот: notifier · Домен: desktop · Классы: H · Для: capability desktop
# Контракт: SLOT-4 (демон — user-юнит на graphical-session.target, DESK-3/DESK-4).
# Юнит — тонкая обёртка над пакетом; конфиг mako — в dotfiles (DOT-3), сюда не входит.
# Зависимости: —
_: {
  flake.modules.homeManager.notifier-mako =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.mako ];

      systemd.user.services.mako = {
        Unit = {
          Description = "Демон уведомлений Wayland (mako)";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.mako}/bin/mako";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}
