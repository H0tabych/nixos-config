# Фича: gaming · Слот: — · Домен: presets · Классы: N+H · Для: пользователей с capability gaming
# Контракт: STR-7 (пресет — только imports). game-platform-steam,
# compat-layer-proton-ge, game-optimizer-gamemode-gamescope, overlay-mangohud — R7.3.
# Зависимости: —
{ config, ... }:
let
  n = config.flake.modules.nixos;
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos.gaming = {
    imports = [
      n.game-platform-steam
      n.compat-layer-proton-ge
      n.game-optimizer-gamemode-gamescope
    ];
  };

  flake.modules.homeManager.gaming = {
    imports = [ hm.overlay-mangohud ];
  };
}
