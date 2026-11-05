# Приватная часть владельца: tunnel-xray · Домен: network
# Контракт: NET-4, NET-7, VPN-CLI-9, VPN-CLI-10, VPN-RTE-3. Входящие соединения клиента
# туннеля (STR-6): выделены из данных политики, когда те перевалили за предел размера.
# Секретов нет (SEC-2). Импортируется и упоминается только в tunnel-xray.nix (C8).
# Зависимости: —
{ lib }:
{
  # Слушатели локального режима: только loopback, адреса и порты — из
  # my.tunnel.local.* (NET-4, VPN-CLI-9). sniffing включён на SOCKS-входе, он
  # получает соединения по IP; у HTTP-прокси имя хоста есть в самом запросе,
  # поэтому там не нужен (VPN-CLI-10). sock-in/http-in не убираются в M2 —
  # они не мешают (слушают только loopback), а убирать их означало бы менять
  # контракт my.tunnel.local.* ради минимального выигрыша.
  # tun-in (M2): системный захват трафика. В settings только name и mtu: адрес и
  # маршруты задаёт ОС, так конфиг не зависит от версии ядра. routeOnly (VPN-RTE-3): домен из sniffing нужен только правилам, цель
  # остаётся исходным IP, иначе правила по IP не сработали бы на этапе без
  # разрешения имён.
  mkInbounds =
    {
      local,
      mode,
      interface,
    }:
    [
      {
        tag = "sock-in";
        listen = local.socks.address;
        port = local.socks.port;
        protocol = "socks";
        settings = {
          udp = true;
          auth = "noauth";
        };
        sniffing = {
          enabled = true;
          destOverride = [
            "http"
            "tls"
          ];
        };
      }
      {
        tag = "http-in";
        listen = local.http.address;
        port = local.http.port;
        protocol = "http";
        settings = { };
      }
    ]
    ++ lib.optional (mode == "m2") {
      tag = "tun-in";
      protocol = "tun";
      settings = {
        inherit (interface) name;
        mtu = 1500;
      };
      sniffing = {
        enabled = true;
        routeOnly = true;
        destOverride = [
          "http"
          "tls"
          "quic"
        ];
      };
    };
}
