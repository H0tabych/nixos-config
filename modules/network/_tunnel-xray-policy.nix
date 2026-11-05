# Приватная часть владельца: tunnel-xray · Домен: network
# Контракт: VPN-RTE-1..9, VPN-DNS-1, VPN-DNS-3, VPN-DNS-5, VPN-DNS-8. Чистые данные и
# функции построения DNS- и routing-секций конфига Xray из my.tunnel.policy.*
# (STR-6): tunnel-xray.nix растёт за счёт данных политики, поэтому они здесь,
# а не в самом юните. Секретов и vnext/users нет — это держит только владелец
# (SEC-2). Импортируется и упоминается только в tunnel-xray.nix (C8).
# Зависимости: —
{ lib }:
let
  # Тот же провайдер и по той же причине IP-литерал, что и dohResolvers ниже.
  otherTypesResolver = "1.1.1.1";
in
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

  # endpoint — адрес выхода. Если это имя, его разрешает прямой резолвер, а не
  # системный: в M2 системный резолвер работает через этот же клиент, и получился
  # бы замкнутый круг. Для IP-литерала запись не срабатывает никогда.
  # route = "direct" (VPN-DNS-8): все имена разрешает резолвер локальной юрисдикции,
  # шифрованного DNS внутри туннеля нет, потому что нет туннеля; имени выхода тоже нет.
  mkDns =
    {
      dnsDirect,
      direct,
      dohResolvers,
      queryStrategy,
      endpoint,
      route,
    }:
    if route == "direct" then
      {
        servers = [ dnsDirect ];
        inherit queryStrategy;
      }
    else
      {
        servers = [
          {
            address = dnsDirect;
            domains = direct ++ [ "full:${endpoint}" ];
            skipFallback = true;
          }
        ]
        ++ dohResolvers;
        inherit queryStrategy;
      };

  # Метка на всех исходящих, а не только на соединении с выходом (VPN-KS-10): без
  # неё прямой трафик клиента в M2 попал бы в таблицу туннеля и зациклился.
  # domainStrategy в sockopt, а не в settings: у freedom он устарел с 26.10.
  mkOutbounds =
    {
      queryStrategy,
      mode,
      mark,
      route,
      dnsDirect,
    }:
    [
      {
        tag = "direct";
        protocol = "freedom";
        settings = { };
        streamSettings.sockopt = {
          inherit mark;
          domainStrategy = queryStrategy;
        };
      }
      {
        tag = "block";
        protocol = "blackhole";
        settings = { };
      }
    ]
    # dns-out (M2): исход для DNS-запросов из tun-in — нужен владельцу
    # routing-правила ниже, который адресует их сюда, а не наружу. A и AAAA идут в
    # DNS-секцию этого конфига (VPN-DNS-1). Других типов она не умеет, и по умолчанию
    # на них уходил бы пустой ответ, поэтому TXT, MX, SRV и прочие идут через туннель
    # к резолверу по DoT (VPN-DNS-9). Без разбора по зонам: это не адресная политика.
    # Маршрут direct (VPN-DNS-8): туннеля нет, поэтому остальные типы уходят тому же
    # резолверу локальной юрисдикции напрямую, с меткой клиента (VPN-KS-10).
    ++ lib.optional (mode == "m2") {
      tag = "dns-out";
      protocol = "dns";
      settings = {
        rules = [
          {
            action = "hijack";
            qType = "1,28";
          }
          { action = "direct"; }
        ];
      }
      // (
        if route == "direct" then
          {
            rewriteNetwork = "udp";
            rewriteAddress = dnsDirect;
            rewritePort = 53;
          }
        else
          {
            rewriteNetwork = "tcp";
            rewriteAddress = otherTypesResolver;
            rewritePort = 853;
          }
      );
      streamSettings =
        if route == "direct" then
          { sockopt = { inherit mark; }; }
        else
          {
            security = "tls";
            tlsSettings.serverName = otherTypesResolver;
            sockopt.dialerProxy = "proxy";
          };
    };

  # Порядок — VPN-RTE-2: домены выше IP, явный catch-all последним. Пустые
  # списки политики пропускаются — Xray не принимает правило без доменов/IP.
  # В M2 первыми — DNS из tun-in (P.3): это не про домены/IP вовсе, а про то,
  # куда уходят запросы самого туннельного интерфейса, поэтому стоят раньше
  # остальных правил. Порт 53 перехватывается у любого адреса, так что и запрос к
  # публичному резолверу напрямую не проходит мимо DNS клиента (VPN-DNS-1). Прочий
  # трафик на точку входа DNS — отказ: это адрес интерфейса, и он вернулся бы сюда же.
  # Адрес dnsDirect идёт напрямую всегда (VPN-DNS-3), даже если хост задал резолвер
  # вне зоны локальной юрисдикции.
  mkRoutingRules =
    {
      block,
      proxy,
      direct,
      directCidrs,
      dnsDirect,
      mode,
      interface,
      route,
      ...
    }:
    lib.optionals (mode == "m2") [
      {
        inboundTag = [ "tun-in" ];
        port = "53";
        outboundTag = "dns-out";
      }
      {
        inboundTag = [ "tun-in" ];
        ip = [ interface.dnsAddress ];
        outboundTag = "block";
      }
    ]
    ++ lib.optional (block != [ ]) {
      domain = block;
      outboundTag = "block";
    }
    # VPN-RTE-9: в маршруте direct эти ресурсы доступны только через туннель, поэтому
    # отказ приходит сразу (KS-3), а не уходит напрямую.
    ++ lib.optional (proxy != [ ]) {
      domain = proxy;
      outboundTag = if route == "direct" then "block" else "proxy";
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
        ip = [ "geoip:private" ] ++ directCidrs ++ [ dnsDirect ];
        outboundTag = "direct";
      }
      {
        ip = [ "geoip:ru" ];
        outboundTag = "direct";
      }
      {
        network = "tcp,udp";
        outboundTag = if route == "direct" then "direct" else "proxy";
      }
    ];
}
