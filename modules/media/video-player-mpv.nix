# Фича: video-player-mpv · Слот: video-player · Домен: media · Классы: H · Для: capability media
# Контракт: слот video-player (ARCHITECTURE.md §6, Приложение A.3); APP-3 —
# аппаратное декодирование видео по умолчанию на встроенной GPU. Конфиг —
# реестр dotfiles (DOT-2/DOT-3): `mpv/mpv.conf` задаёт `hwdec=vaapi` и
# `vaapi-device=/dev/dri/by-host/igpu-render` (ролевая ссылка render-ноды,
# фича `gpu-hybrid` — не host-константа, DOT-3). Render-нода, не card:
# ПРОВЕРЕНО на машине (R7.2) — автоопределение драйвера libva падает на
# card-ноде (`vaGetDriverNames` → "operation failed", mpv молча уходит на
# программный декодер) и работает верно на renderD12x. `include=` подключает
# сгенерированный `mpv/theme.conf` (DSN-S9/R7.2: DSN-CMP-19, шрифт UI и цвета
# OSD из палитры). `hardware.graphics`/`intel-media-driver` — фича
# `gpu-integrated` (nixos, уже подключена хостом).
# Зависимости: —
_: {
  flake.modules.homeManager.video-player-mpv = { pkgs, ... }: {
    home.packages = [ pkgs.mpv ];
  };
}
