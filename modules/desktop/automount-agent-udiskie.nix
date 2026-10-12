# Фича: automount-agent-udiskie · Слот: automount-agent · Домен: desktop · Классы: H · Для: capability desktop
# Контракт: SLOT-4 (демон — user-юнит на graphical-session.target, обеспечивает
# сам HM-модуль services.udiskie). Зависит от hardware/automount (services.udisks2) —
# выражено assertions, а не импортом фичи (ARCH-3). Трей выключен (tray = "never"):
# наличие трея в waybar не проверено (конфиг — в dotfiles, DOT-3), а без host
# трея юнит будет ждать tray.target. Уведомление о монтировании — через mako.
# Зависимости: —
_: {
  flake.modules.homeManager.automount-agent-udiskie =
    { osConfig, ... }:
    {
      assertions = [
        {
          assertion = osConfig.services.udisks2.enable;
          message = "automount-agent-udiskie требует включённую фичу hardware/automount (services.udisks2.enable)";
        }
      ];

      services.udiskie = {
        enable = true;
        tray = "never";
      };
    };
}
