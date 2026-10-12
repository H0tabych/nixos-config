# Фича: clipboard-cliphist · Слот: clipboard · Домен: desktop · Классы: H · Для: capability desktop
# Контракт: SLOT-4 (демон — user-юнит на graphical-session.target). Юнит — тонкая
# обёртка над пакетом (DESK-4); юнит из самого пакета cliphist (bin/cliphist.service)
# не используется — в нём зашит FHS-путь /usr/bin/wl-paste, на NixOS нерабочий.
# MIME определяется wl-paste автоматически (без --type): cliphist store сам
# различает текст и изображения.
# Зависимости: —
_: {
  flake.modules.homeManager.clipboard-cliphist =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.cliphist
        pkgs.wl-clipboard
      ];

      systemd.user.services.cliphist = {
        Unit = {
          Description = "Вотчер буфера обмена cliphist";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}
