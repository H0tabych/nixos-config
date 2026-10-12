# Фича: osd-swayosd · Слот: osd · Домен: desktop · Классы: N+H · Для: capability desktop
# Контракт: SLOT-4. swayosd разделён на два демона: swayosd-libinput-backend
# (системный, нужен доступ к /dev/input — N) и swayosd-server (пользовательский
# GUI-демон — H, user-юнит на graphical-session.target, DESK-3/DESK-4).
# Юнит swayosd-libinput-backend описан опциями NixOS напрямую, а не через
# systemd.packages: юнит пакета несёт After=/PartOf=/WantedBy=graphical.target,
# а systemd не умеет сбрасывать After=/Before= дроп-ином (man systemd.syntax(7):
# пустым значением сбрасываются только директивы, где это явно документировано
# — After=/Before= туда не входят, проверено и описанием, и локальным
# экспериментом). Поэтому юнит пакета не подключаем вовсе — иначе
# wantedBy=multi-user.target замыкает цикл (multi-user.target ждёт этот юнит,
# юнит ждёт graphical.target, graphical.target ждёт multi-user.target).
# Зависимости: —
_: {
  flake.modules.nixos.osd-swayosd =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.swayosd ];
      systemd.services.swayosd-libinput-backend = {
        description = "SwayOSD LibInput backend for listening to certain keys like CapsLock, ScrollLock, VolumeUp, etc...";
        documentation = [ "https://github.com/ErikReider/SwayOSD" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "dbus";
          BusName = "org.erikreider.swayosd";
          ExecStart = "${pkgs.swayosd}/bin/swayosd-libinput-backend";
          Restart = "on-failure";
        };
      };
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
