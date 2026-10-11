# Фича: tunnel · Слот: — · Домен: presets · Классы: N · Для: хостов с туннелем (не vm)
# Контракт: STR-7 (пресет — только imports); VPN_SUBSYSTEM 2.1. killswitch,
# dns-resolver добавятся в R5.4 (режим M2) — сейчас их нет в репозитории.
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
    ];
  };
}
