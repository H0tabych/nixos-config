# Фича: tunnel · Слот: — · Домен: presets · Классы: N · Для: хостов с туннелем (не vm)
# Контракт: STR-7 (пресет — только imports); VPN_SUBSYSTEM 2.1. dns-resolver и
# killswitch активны только в режиме m2 (их фичи сами проверяют my.tunnel.mode).
# Зависимости: —
{ config, ... }:
let
  n = config.flake.modules.nixos;
in
{
  flake.modules.nixos.tunnel = {
    imports = [
      n.tunnel-facts
      n.tunnel-xray
      n.dns-resolver
      n.killswitch
    ];
  };
}
