# Фича: laptop · Слот: — · Домен: presets · Классы: N · Для: хостов класса laptop
# Контракт: STR-7 (пресет — только imports). swap, maintenance добавятся в R5.1/R5.2.
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
    ];
  };
}
