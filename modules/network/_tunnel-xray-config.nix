# Приватная часть владельца: tunnel-xray · Домен: network
# Контракт: VPN-CLI-2, VPN-CLI-4, VPN-RTE-9, VPN-MOD-8, VPN-MOD-11, NET-13. Сборка двух
# конфигов клиента из одной политики (STR-6): tunnel-xray.nix растёт за счёт них.
#   tunnel — catch-all → выход; содержит плейсхолдеры секретов (SEC-4), рендерится
#            sops-nix при активации;
#   direct — catch-all → напрямую; исходящего к выходу нет, секретов нет вовсе,
#            поэтому он целиком лежит в /nix/store и не зависит от ключей sops.
# Импортируется и упоминается только в tunnel-xray.nix (C8).
# Зависимости: —
# policy — данные и функции политики (DNS, исходящие, правила, входящие): их импортирует
# владелец и передаёт сюда, чтобы другие файлы не знали об их именах (C8).
{ lib, policy }:
{
  # cfg — config.my.tunnel; ph — config.sops.placeholder.<имя> (нужен только tunnel).
  mkConfigs =
    { cfg, ph }:
    let
      inherit (cfg) mode;
      inherit (cfg.killswitch) mark;
      m2 = mode == "m2";
      queryStrategy = if cfg.ipv6 == "blocked" then "UseIPv4" else "UseIP";

      proxyOutbound = {
        tag = "proxy";
        protocol = "vless";
        settings.vnext = [
          {
            address = ph "tunnel.endpoint";
            port = 443; # константа контракта VPN-SRV-3, не секрет
            users = [
              {
                id = ph "tunnel.clientId";
                encryption = "none";
                flow = "xtls-rprx-vision";
              }
            ];
          }
        ];
        streamSettings = {
          network = "tcp";
          security = "reality";
          realitySettings = {
            serverName = ph "tunnel.serverName";
            publicKey = ph "tunnel.serverKey";
            shortId = ph "tunnel.shortId";
            fingerprint = ph "tunnel.fingerprint";
            spiderX = "/";
            # Пустая строка = проверка выключена. Заполнить ключом проверки
            # сразу после включения подписи на выходе (VPN-SRV-3).
            mldsa65Verify = "";
          };
          # domainStrategy: если адрес выхода — имя, его разрешает DNS-секция
          # этого конфига, а не системный резолвер (см. mkDns).
          sockopt = {
            inherit mark;
            domainStrategy = queryStrategy;
          };
        };
      };

      mk = route: {
        # access = "none": иначе адресат каждого соединения попадает в журнал на любом
        # уровне (VPN-CLI-8), а в M2 это весь трафик машины.
        log = {
          loglevel = "warning";
          access = "none";
        };
        dns = policy.mkDns {
          inherit (cfg.policy) dnsDirect direct;
          inherit queryStrategy route;
          inherit (policy) dohResolvers;
          endpoint = if route == "tunnel" then ph "tunnel.endpoint" else "";
        };
        inbounds = policy.mkInbounds { inherit (cfg) local mode interface; };
        outbounds =
          lib.optional (route == "tunnel") proxyOutbound
          ++ policy.mkOutbounds {
            inherit
              mode
              mark
              queryStrategy
              route
              ;
            inherit (cfg.policy) dnsDirect;
          };
        routing = {
          domainStrategy = if m2 then "AsIs" else "IPOnDemand";
          rules = policy.mkRoutingRules (
            cfg.policy // { inherit (cfg) mode interface; } // { inherit route; }
          );
        };
      };
    in
    {
      tunnel = mk "tunnel";
      direct = mk "direct";
    };
}
