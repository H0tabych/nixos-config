# Фича: wallpaper-hyprpaper · Слот: wallpaper · Домен: desktop · Классы: H · Для: capability desktop
# Контракт: SLOT-4 (демон — user-юнит на graphical-session.target). Юнит — тонкая
# обёртка над пакетом (DESK-4); конфиг hyprpaper — в dotfiles (DOT-3).
# Зависимости: —
_: {
  flake.modules.homeManager.wallpaper-hyprpaper =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.hyprpaper ];

      systemd.user.services.hyprpaper = {
        Unit = {
          Description = "Демон обоев Wayland (hyprpaper)";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.hyprpaper}/bin/hyprpaper";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}
