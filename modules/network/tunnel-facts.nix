# Фича: tunnel-facts · Слот: — · Домен: network · Классы: N · Для: хоста с пресетом tunnel
# Контракт: ARCH-4, VPN_SUBSYSTEM 2.3, VPN-RTE-4..6, VPN-DNS-3/4, VPN-INT-5.
# Объявление my.tunnel.* и публичных умолчаний (аналог host-facts); значений
# секретов здесь нет (SEC-2). Опции режима M2 (killswitch, bypass, dns.scopedZones)
# объявлены в приватной части _tunnel-facts-m2.nix (STR-6).
# Зависимости: —
_: {
  flake.modules.nixos.tunnel-facts =
    { lib, ... }:
    {
      options.my.tunnel = {
        mode = lib.mkOption {
          type = lib.types.enum [
            "m1"
            "m2"
          ];
          default = "m1";
          description = "Режим клиента туннеля (NET-7); m2 — цель R5.4.";
        };

        local = {
          socks = {
            address = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
              description = "Адрес loopback-прокси SOCKS (NET-4).";
            };
            port = lib.mkOption {
              type = lib.types.port;
              default = 10808;
              description = "Порт loopback-прокси SOCKS (M1).";
            };
          };
          http = {
            address = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
              description = "Адрес loopback-прокси HTTP (NET-4).";
            };
            port = lib.mkOption {
              type = lib.types.port;
              default = 10809;
              description = "Порт loopback-прокси HTTP (M1).";
            };
          };
          noProxy = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "localhost"
              "127.0.0.1"
              "::1"
              ".local"
              ".ru"
              ".su"
              ".xn--p1ai"
            ];
            description = "Исключения прокси-переменных M1 (VPN_SUBSYSTEM, приложение).";
          };
        };

        policy = {
          direct = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "geosite:category-ru"
              "domain:ru"
              "domain:su"
              "domain:xn--p1ai"
            ];
            description = "Домены и geo-теги для прямого соединения (VPN-RTE-4).";
          };
          proxy = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Домены принудительно через туннель; приоритетнее direct (VPN-RTE-5).";
          };
          block = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Блокируемые домены; включается осознанно (VPN-RTE-6).";
          };
          directCidrs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Сети напрямую сверх частных, например корпоративный VPN (VPN-INT-5).";
          };
          dnsDirect = lib.mkOption {
            type = lib.types.str;
            # Яндекс.DNS — публичный резолвер локальной юрисдикции; при другом
            # провайдере или RTT переопределяется хостом (VPN-DNS-3).
            default = "77.88.8.8";
            description = "Резолвер локальной юрисдикции для доменов direct (VPN-DNS-3).";
          };
        };

        ipv6 = lib.mkOption {
          type = lib.types.enum [
            "blocked"
            "tunneled"
          ];
          default = "blocked";
          description = "Политика IPv6; tunneled — только после проверки выхода (VPN-DNS-4).";
        };
      }
      # Опции режима M2 (kill switch, обход, класс `scoped`) — в приватной части
      # рядом с владельцем: файл перевалил за 150 строк (STR-6, C6).
      // (import ./_tunnel-facts-m2.nix { inherit lib; }).m2Options;
    };
}
