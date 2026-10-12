# Фича: polkit-agent-hyprpolkitagent · Слот: polkit-agent · Домен: desktop · Классы: N+H · Для: capability desktop
# Контракт: SLOT-4. N — включает security.polkit.enable (по умолчанию выключен,
# без него агент не сможет обрабатывать запросы авторизации); H — демон-агент,
# user-юнит на graphical-session.target (DESK-3/DESK-4).
# Зависимости: —
_: {
  flake.modules.nixos.polkit-agent-hyprpolkitagent = {
    security.polkit.enable = true;
  };

  flake.modules.homeManager.polkit-agent-hyprpolkitagent =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.hyprpolkitagent ];

      systemd.user.services.hyprpolkitagent = {
        Unit = {
          Description = "Агент авторизации polkit (Hyprland)";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}
