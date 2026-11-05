# Фича: bluetooth-manager-blueman · Слот: bluetooth-manager · Домен: desktop · Классы: N+H · Для: capability desktop
# Контракт: SLOT-4. N — services.blueman.enable (пакет, polkit-механизм
# org.blueman.Mechanism, D-Bus активация); зависит от hardware/bluetooth
# (hardware.bluetooth.enable) — выражено assertions, а не импортом фичи (ARCH-3).
# H — демон-аплет, user-юнит на graphical-session.target (DESK-3/DESK-4); значок
# в трее не показывается (плагин StatusIcon отключён, ADR-42): Bluetooth — модуль самой
# панели (dotfiles eww/, net/bluetooth); агент сопряжения и менеджер остаются.
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

      # `!` перед именем — отключение плагина (PluginManager blueman, ключ по умолчанию
      # пуст, поэтому остальные плагины не затронуты). Без StatusIcon значок в трее не
      # создаётся; AuthAgent (запросы сопряжения) работает как раньше.
      dconf.settings."org/blueman/general".plugin-list = [ "!StatusIcon" ];

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
