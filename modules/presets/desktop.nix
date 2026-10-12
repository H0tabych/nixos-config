# Фича: desktop · Слот: — · Домен: presets · Классы: N+H · Для: пользователей с capability desktop
# Контракт: STR-7 (пресет — только imports), R4.3. Реализации слотов — по
# Приложению A.3 Архитектуры. terminal-foot/file-manager-yazi живут в домене
# shell (ARCHITECTURE.md §6: это командная строка пользователя), но подключаются
# именно отсюда — их владелец по использованию - capability desktop (STRUCTURE.md,
# «правило выбора домена»).
# Зависимости: —
{ config, ... }:
let
  n = config.flake.modules.nixos;
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos.desktop = {
    imports = [
      n.session-hyprland
      n.display-manager-sddm
      n.bar-waybar
      n.lockscreen-hyprlock
      n.idle-hypridle
      n.polkit-agent-hyprpolkitagent
      n.osd-swayosd
      n.theme
    ];
  };

  flake.modules.homeManager.desktop = {
    imports = [
      hm.notifier-mako
      hm.launcher-rofi
      hm.wallpaper-hyprpaper
      hm.screenshot-grim
      hm.clipboard-cliphist
      hm.polkit-agent-hyprpolkitagent
      hm.osd-swayosd
      hm.terminal-foot
      hm.file-manager-yazi
      hm.theme
    ];
  };
}
