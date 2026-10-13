# Фича: laptop · Слот: — · Домен: presets · Классы: N · Для: хостов класса laptop
# Контракт: STR-7 (пресет — только imports).
# Зависимости: —
{ config, ... }:
let
  n = config.flake.modules.nixos;
in
{
  flake.modules.nixos.laptop = {
    imports = [
      n.power
      n.sleep
      n.firmware
      n.audio
      n.bluetooth
      n.automount
      n.layout
      n.swap
      n.maintenance
      n.backup
    ];
  };
}
