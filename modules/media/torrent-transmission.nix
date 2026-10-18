# Фича: torrent-transmission · Слот: torrent · Домен: media · Классы: H · Для: capability media
# Контракт: слот torrent (ARCHITECTURE.md §6, Приложение A.3); VPN-A6 —
# торрент-клиент не отправляет трафик на выход. Transmission не умеет
# проксировать пиринговые соединения через SOCKS/HTTP (нет такой настройки ни
# в GTK-клиенте, ни в libtransmission) — раздача идёт напрямую независимо от
# прокси-переменных UWSM-сессии (DOT-7). Протокол BitTorrent дополнительно
# маршрутизируется `direct` в самой фиче tunnel-xray (VPN-RTE-2), если
# трафик всё же попадёт в SOCKS. «Слайс обхода» (VPN-INT-3,
# `my.tunnel.bypass.units`, MAY) здесь не заводится: опцию читает только
# фича killswitch, которая не активна в M1 — обходить нечего; решение
# осознанное (R7.2), слайс — предмет шага M2 (R5.5).
# pkgs.transmission_4-gtk — актуальный атрибут 26.05; transmission(-gtk) без
# суффикса — алиасы-throw на transmission_3 (убран из-за риска потери данных).
# Зависимости: —
_: {
  flake.modules.homeManager.torrent-transmission = { pkgs, ... }: {
    home.packages = [ pkgs.transmission_4-gtk ];
  };
}
