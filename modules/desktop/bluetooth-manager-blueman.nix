# Фича: bluetooth-manager-blueman · Слот: bluetooth-manager · Домен: desktop · Классы: N+H · Для: capability desktop
# Контракт: SLOT-4. N — services.blueman.enable (пакет, polkit-механизм
# org.blueman.Mechanism, D-Bus активация); зависит от hardware/bluetooth
# (hardware.bluetooth.enable) — выражено assertions, а не импортом фичи (ARCH-3).
# H — демон-аплет, user-юнит на graphical-session.target (DESK-3/DESK-4); значок
# в трее отображает существующий модуль tray в waybar (dotfiles, DOT-3).
# Зависимости: —
_: {
  flake.modules.nixos.bluetooth-manager-blueman =
    { config, ... }:
    {
      assertions = [
        {
          assertion = config.hardware.bluetooth.enable;
          message = "bluetooth-manager-blueman требует включённую фичу hardware/bluetooth (hardware.bluetooth.enable)";
        }
      ];

      services.blueman.enable = true;
    };

  flake.modules.homeManager.bluetooth-manager-blueman =
    { pkgs, osConfig, ... }:
    {
      assertions = [
        {
          assertion = osConfig.hardware.bluetooth.enable;
          message = "bluetooth-manager-blueman требует включённую фичу hardware/bluetooth (hardware.bluetooth.enable)";
        }
      ];

      systemd.user.services.blueman-applet = {
        Unit = {
          Description = "Аплет Bluetooth (blueman)";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.blueman}/bin/blueman-applet";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}
