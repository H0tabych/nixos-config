# Фича: tunnel-xray · Слот: tunnel · Домен: network · Классы: N · Для: хоста с пресетом tunnel
# Контракт: VPN-CLI-1..9, VPN-MOD-2/4, NET-1..4, NET-9, SEC-4, VPN-RTE-1..8,
# VPN-DNS-1, VPN-DNS-3..5. Единственный владелец юнита tunnel-xray и его конфига
# (VPN-CLI-1). Конфиг рендерится sops-nix из шаблона при старте — в /nix/store
# попадают только плейсхолдеры (VPN-CLI-2).
# Прокси-переменные графической сессии (NET-10, DOT-7) эта фича НЕ доставляет:
# env-файл менеджера сессий принадлежит слоту session (session-hyprland), иначе
# замена композитора (DESK-10) потребовала бы правки сетевой фичи (ARCH-16, SLOT-3).
# Постквантовая подпись (mldsa65Verify) не заполняется: выход её пока не
# выпускает (VPN-SRV-3 не выполнен на сервере) — это отступление, а не исключение
# по VPN-CLI-3 (ядро xray-core проверку поддерживает); запись со сроком
# пересмотра — в docs/runbook/tunnel.md.
# DNS и routing строятся из my.tunnel.policy.* данными _tunnel-xray-policy.nix
# (STR-6); domainStrategy = "IPOnDemand" — M1 (VPN-RTE-3), R5.4 заменит на "AsIs"
# и добавит tun-in/dns-out (P.3).
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

      queryStrategy = if cfg.ipv6 == "blocked" then "UseIPv4" else "UseIP";

      xrayConfig = {
        log.loglevel = "warning";
        dns = policy.mkDns {
          inherit (cfg.policy) dnsDirect direct;
          inherit queryStrategy;
          inherit (policy) dohResolvers;
        };
        inbounds = policy.mkInbounds { inherit (cfg) local; };
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
                # Пустая строка = проверка выключена. Заполнить ключом проверки
                # сразу после включения подписи на выходе (VPN-SRV-3).
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

      systemd.services.tunnel-xray = {
        description = "Клиент туннеля (VLESS + Reality, M1)";
        wantedBy = [ "multi-user.target" ];
        # sops-nix рендерит секреты и шаблоны в system.activationScripts.setupSecrets,
        # юнита sops-nix.service не существует — ordering к нему systemd молча
        # игнорировал. Активация идёт до старта юнитов, поэтому файл шаблона уже
        # на месте; перерисовку при смене значения обеспечивает restartUnits
        # у sops.templates.tunnel-xray ниже.
        after = [ "network-online.target" ];
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
