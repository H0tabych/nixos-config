# Фича: media · Слот: — · Домен: presets · Классы: N · Для: пользователей с capability media
# Контракт: STR-7 (пресет — только imports). Браузер (R4.5); video-player-mpv,
# torrent-transmission добавятся позже (фаза 7).
# Зависимости: —
{ config, ... }:
let
  n = config.flake.modules.nixos;
in
{
  flake.modules.nixos.media = {
    imports = [ n.browser-firefox ];
  };
}
