# Фича: media · Слот: — · Домен: presets · Классы: N+H · Для: пользователей с capability media
# Контракт: STR-7 (пресет — только imports). Браузер (R4.5); video-player-mpv,
# torrent-transmission — R7.2.
# Зависимости: —
{ config, ... }:
let
  n = config.flake.modules.nixos;
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos.media = {
    imports = [ n.browser-firefox ];
  };

  flake.modules.homeManager.media = {
    imports = [
      hm.video-player-mpv
      hm.torrent-transmission
    ];
  };
}
