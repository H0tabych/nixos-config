# Фича: tunnel-xray · Слот: tunnel · Домен: network · Классы: N · Для: хоста с пресетом tunnel
# Контракт: VPN-CLI-1..9, VPN-MOD-2/4, NET-1..4, NET-9, NET-10, SEC-4, VPN-RTE-1..8,
# VPN-DNS-1, VPN-DNS-3..5. Единственный владелец юнита tunnel-xray и его конфига
# (VPN-CLI-1). Конфиг рендерится sops-nix из шаблона при старте — в /nix/store
# попадают только плейсхолдеры (VPN-CLI-2). Постквантовая подпись (mldsa65Verify)
# сейчас не заполняется: сервер её не выпускает (VPN-CLI-3 — документированное
# исключение до правки сервера). DNS и routing строятся из my.tunnel.policy.*
# данными _tunnel-xray-policy.nix (STR-6); domainStrategy = "IPOnDemand" — M1
# (VPN-RTE-3), R5.4 заменит на "AsIs" и добавит tun-in/dns-out (P.3).
# Режим M2 (TUN, killswitch, R5.4) — только зарезервированная ветка по my.tunnel.mode.
# Зависимости: host-facts (my.host.name), tunnel-facts (my.tunnel.*; через
# config.my.*, не import — ARCH-3).
{ config, ... }:
let
  outer = config;
  secretsFile = outer.flake.lib.repo.secrets;
in
{
  flake.modules.nixos.tunnel-xray =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.my.tunnel;
      pkg = pkgs.xray;
      ph = name: config.sops.placeholder.${name};
      policy = import ./_tunnel-xray-policy.nix { inherit lib; };

      httpProxyUrl = "http://${cfg.local.http.address}:${toString cfg.local.http.port}";
      socksProxyUrl = "socks5h://${cfg.local.socks.address}:${toString cfg.local.socks.port}";
      noProxyStr = lib.concatStringsSep "," cfg.local.noProxy;
      queryStrategy = if cfg.ipv6 == "blocked" then "UseIPv4" else "UseIP";

      xrayConfig = {
        log.loglevel = "warning";
        dns = policy.mkDns {
          inherit (cfg.policy) dnsDirect direct;
          inherit queryStrategy;
          inherit (policy) dohResolvers;
        };
        inbounds = [
          {
            tag = "sock-in";
            listen = cfg.local.socks.address;
            port = cfg.local.socks.port;
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
            listen = cfg.local.http.address;
            port = cfg.local.http.port;
            protocol = "http";
            settings = { };
          }
        ];
        outbounds = [
          {
            tag = "proxy";
            protocol = "vless";
            settings = {
              vnext = [
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
            };
            streamSettings = {
              network = "tcp";
              security = "reality";
              realitySettings = {
                serverName = ph "tunnel.serverName";
                publicKey = ph "tunnel.serverKey";
                shortId = ph "tunnel.shortId";
                fingerprint = ph "tunnel.fingerprint";
                spiderX = "/";
                mldsa65Verify = "";
              };
            };
          }
        ]
        ++ policy.mkOutbounds { inherit (cfg) ipv6; };
        routing = {
          domainStrategy = "IPOnDemand";
          rules = policy.mkRoutingRules cfg.policy;
        };
      };
    in
    {
      sops.secrets = {
        "tunnel.endpoint".sopsFile = secretsFile "common.yaml";
        "tunnel.serverKey".sopsFile = secretsFile "common.yaml";
        "tunnel.serverName".sopsFile = secretsFile "common.yaml";
        "tunnel.fingerprint".sopsFile = secretsFile "common.yaml";
        "tunnel.clientId".sopsFile = secretsFile "hosts/${config.my.host.name}.yaml";
        "tunnel.shortId".sopsFile = secretsFile "hosts/${config.my.host.name}.yaml";
      };

      sops.templates.tunnel-xray = {
        path = "/run/secrets/rendered/tunnel-xray.json";
        mode = "0400";
        content = builtins.toJSON xrayConfig;
        restartUnits = [ "tunnel-xray.service" ];
      };

      environment.sessionVariables = lib.mkIf (cfg.mode == "m1") {
        http_proxy = httpProxyUrl;
        HTTP_PROXY = httpProxyUrl;
        https_proxy = httpProxyUrl;
        HTTPS_PROXY = httpProxyUrl;
        all_proxy = socksProxyUrl;
        ALL_PROXY = socksProxyUrl;
        no_proxy = noProxyStr;
        NO_PROXY = noProxyStr;
      };

      systemd.services.tunnel-xray = {
        description = "Клиент туннеля (VLESS + Reality, M1)";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "sops-nix.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          DynamicUser = true;
          LoadCredential = "config.json:${config.sops.templates.tunnel-xray.path}";
          ExecStartPre = "${pkg}/bin/xray run -test -c %d/config.json";
          ExecStart = "${pkg}/bin/xray run -c %d/config.json";
          Restart = "on-failure";
          RestartSec = 2;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          # M1: без доп. привилегий (VPN-CLI-5); M2 (R5.4) добавит CAP_NET_ADMIN (ARCH-6).
          CapabilityBoundingSet = lib.optionals (cfg.mode == "m2") [ "CAP_NET_ADMIN" ];
          AmbientCapabilities = lib.optionals (cfg.mode == "m2") [ "CAP_NET_ADMIN" ];
        };
      };
    };
}
