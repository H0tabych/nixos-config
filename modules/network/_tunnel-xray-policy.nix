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
  dohResolvers = [
    "https://cloudflare-dns.com/dns-query"
    "https://dns.quad9.net/dns-query"
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
