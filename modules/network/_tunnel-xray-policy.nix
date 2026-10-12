# Приватная часть владельца: tunnel-xray · Домен: network
# Контракт: VPN-RTE-1..8, VPN-DNS-1, VPN-DNS-3, VPN-DNS-5. Чистые данные и
# функции построения DNS- и routing-секций конфига Xray из my.tunnel.policy.*
# (STR-6): tunnel-xray.nix растёт за счёт данных политики, поэтому они здесь,
# а не в самом юните. Секретов и vnext/users нет — это держит только владелец
# (SEC-2). Импортируется и упоминается только в tunnel-xray.nix (C8).
# Зависимости: —
{ lib }:
{
  # Публичные DoH-резолверы для доменов, уходящих в туннель (не секрет, не
  # опция my.* — такой же случай, как порт 443 в tunnel-xray.nix).
  # Адреса заданы IP-литералами, а не доменами: имя DoH-сервера пришлось бы
  # сначала разрешить, а в этой DNS-секции для него нет сервера (у прямого
  # резолвера skipFallback = true и список domains), поэтому бутстрап-запрос
  # уходил бы системному резолверу провайдера — против NET-5. Сертификаты
  # Cloudflare и Quad9 покрывают эти IP, поэтому DoH по IP работает.
  dohResolvers = [
    "https://1.1.1.1/dns-query"
    "https://9.9.9.9/dns-query"
  ];

  mkDns =
    {
      dnsDirect,
      direct,
      dohResolvers,
      queryStrategy,
    }:
    {
      servers = [
        {
          address = dnsDirect;
          domains = direct;
          skipFallback = true;
        }
      ]
      ++ dohResolvers;
      inherit queryStrategy;
    };

  # Слушатели локального режима: только loopback, адреса и порты — из
  # my.tunnel.local.* (NET-4, VPN-CLI-9). sniffing включён на SOCKS-входе, он
  # получает соединения по IP; у HTTP-прокси имя хоста есть в самом запросе,
  # поэтому там не нужен (VPN-CLI-10).
  mkInbounds =
    { local }:
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
    ];

  mkOutbounds = { ipv6 }: [
    {
      tag = "direct";
      protocol = "freedom";
      settings.domainStrategy = if ipv6 == "blocked" then "UseIPv4" else "UseIP";
    }
    {
      tag = "block";
      protocol = "blackhole";
      settings = { };
    }
  ];

  # Порядок — VPN-RTE-2: домены выше IP, явный catch-all последним. Пустые
  # списки политики пропускаются — Xray не принимает правило без доменов/IP.
  mkRoutingRules =
    {
      block,
      proxy,
      direct,
      directCidrs,
      ...
    }:
    lib.optional (block != [ ]) {
      domain = block;
      outboundTag = "block";
    }
    ++ lib.optional (proxy != [ ]) {
      domain = proxy;
      outboundTag = "proxy";
    }
    ++ lib.optional (direct != [ ]) {
      domain = direct;
      outboundTag = "direct";
    }
    ++ [
      {
        protocol = [ "bittorrent" ];
        outboundTag = "direct";
      }
      {
        ip = [ "geoip:private" ] ++ directCidrs;
        outboundTag = "direct";
      }
      {
        ip = [ "geoip:ru" ];
        outboundTag = "direct";
      }
      {
        network = "tcp,udp";
        outboundTag = "proxy";
      }
    ];
}
