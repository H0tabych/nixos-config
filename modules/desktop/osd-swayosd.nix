# Фича: osd-swayosd · Слот: osd · Домен: desktop · Классы: N+H · Для: capability desktop
# Контракт: SLOT-4. swayosd разделён на два демона: swayosd-libinput-backend
# (системный, нужен доступ к /dev/input — N) и swayosd-server (пользовательский
# GUI-демон — H, user-юнит на graphical-session.target, DESK-3/DESK-4).
# systemd.packages подключает системный юнит, который несёт сам пакет.
# Зависимости: —
_: {
  flake.modules.nixos.osd-swayosd =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.swayosd ];
      systemd.packages = [ pkgs.swayosd ];
      systemd.services.swayosd-libinput-backend.wantedBy = [ "multi-user.target" ];
    };

  flake.modules.homeManager.osd-swayosd =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.swayosd ];

      systemd.user.services.swayosd-server = {
        Unit = {
          Description = "Демон экранных индикаторов (swayosd)";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.swayosd}/bin/swayosd-server";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}
