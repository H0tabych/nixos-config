# Фича: tunnel-facts · Слот: — · Домен: network · Классы: N · Для: хоста с пресетом tunnel
# Контракт: ARCH-4, VPN_SUBSYSTEM 2.3. Объявление my.tunnel.* и публичных умолчаний
# (аналог host-facts); значений секретов здесь нет (SEC-2). Полная таблица 2.3
# (policy.*, ipv6, killswitch.allowedInterfaces, bypass.units) появится при
# потребителях — R3.4 (политика) и R5.4 (режим M2).
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
      };
    };
}
