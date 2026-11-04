# Фича: killswitch · Слот: — · Домен: network · Классы: N · Для: хостов с туннелем в M2
# Контракт: VPN-KS-1..9, VPN-KS-11, NET-8. Владеет собственной таблицей nftables,
# независимой от firewall (ARCH-1, L-1: делить владение таблицей нельзя).
#
# VPN-KS-3 — **отказ, а не отбрасывание**. У цепочки nftables policy бывает
# только accept или drop, поэтому отказ даёт последнее явное правило
# `reject with icmpx type admin-prohibited`, а `policy drop` остаётся
# подстраховкой за ним. Клиент получает ошибку сразу, а не висит до таймаута:
# это условие AI-GW-5/AI-A9 (уход на локальную роль за ≤ 10 с).
#
# VPN-KS-2 — трафик самого клиента опознаётся по **метке** (my.tunnel.killswitch.mark),
# не по адресу выхода (тот секрет, SEC-4) и не по uid: юнит идёт с DynamicUser.
# VPN-KS-7 — имён интерфейсов хоста и его адресов в правилах нет: роли «loopback»,
# «линк туннеля» (my.tunnel.interface.name) и «разрешённые линки» из политики.
# VPN-KS-8 — таблица не привязана к юниту клиента: при его остановке и при
# suspend/hibernate правила остаются, окна без правил нет.
# VPN-KS-9 — восстановление: консоль и откат поколения доступны всегда, правила
# не трогают входящий трафик и loopback (процедуры KS-6/KS-9 — runbook/tunnel.md).
# VPN-KS-11 — общего разрешения `ct state established` нет: при остановке клиента
# такое правило пропускало бы открытые соединения на физический интерфейс.
#
# В M1 фича не активна: VPN-KS-1 делает kill switch обязательным именно в M2, а
# в M1 трафик идёт напрямую — отказ по умолчанию отрезал бы сеть целиком.
# Откат режима — один параметр my.tunnel.mode.
# Зависимости: tunnel-facts (my.tunnel.*) — только чтение, firewall (nftables) —
# только assertion (ARCH-3).
_: {
  flake.modules.nixos.killswitch =
    { config, lib, ... }:
    let
      cfg = config.my.tunnel;

      tunnelLink = cfg.interface.name;

      allowed = cfg.killswitch.allowedInterfaces;
      allowedRule =
        lib.optionalString (allowed != [ ])
          "oifname { ${lib.concatMapStringsSep ", " (i: ''"${i}"'') allowed} } accept";

      ipv6Blocked = cfg.ipv6 == "blocked";

      reject = "reject with icmpx type admin-prohibited";

      # Локальная сеть (VPN-RTE-4): принтеры, NAS, локальный инференс, контейнеры —
      # не через туннель никогда. Multicast и ff00::/8 — её служебный трафик:
      # обнаружение устройств и NDP (VPN-KS-2).
      lanRules = ''
        ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4 } accept
        ip6 daddr { fe80::/10, fc00::/7, ff00::/8 } accept
      '';

      ipv6Rule = lib.optionalString ipv6Blocked ''
        # VPN-DNS-4: исходящий IPv6 вне туннеля — отказом, не молча.
        meta nfproto ipv6 ${reject}
      '';
    in
    lib.mkIf (cfg.mode == "m2") {
      assertions = [
        {
          assertion = config.networking.nftables.enable;
          message = "killswitch требует nftables (фича firewall): без них таблица не загрузится";
        }
      ];

      # Имя таблицы фиксировано: процедура KS-6 (временное снятие на время
      # портала авторизации) должна работать с предсказуемым объектом.
      networking.nftables.tables.killswitch = {
        family = "inet";
        content = ''
          chain output {
            type filter hook output priority filter; policy drop;

            oifname "lo" accept
            oifname "${tunnelLink}" accept

            ${allowedRule}

            # KS-2: сам клиент туннеля — по метке.
            meta mark ${toString cfg.killswitch.mark} accept

            # Служебный трафик локальной сети: DHCP.
            udp dport { 67, 68 } accept

            # KS-5: DNS и DoT мимо туннеля режутся ДО общего разрешения
            # локальной сети — иначе запросы утекают через домашний
            # маршрутизатор. Порядок правил здесь и есть смысл KS-5.
            meta l4proto { tcp, udp } th dport 53 ${reject}
            meta l4proto { tcp, udp } th dport 853 ${reject}

            ${lanRules}
            ${ipv6Rule}

            # KS-3: прочее — отказ, не тишина.
            ${reject}
          }

          # KS-4: пересылаемый трафик (контейнеры, виртуальные мосты). Наружу —
          # только через туннель. Адресат в локальной сети проходит: это соединения
          # между контейнерами и ответы контейнерам, в том числе пришедшие из туннеля.
          chain forward {
            type filter hook forward priority filter; policy drop;

            oifname "${tunnelLink}" accept
            ${allowedRule}
            meta l4proto { tcp, udp } th dport 53 ${reject}

            ${lanRules}
            ${ipv6Rule}
            ${reject}
          }
        '';
      };
    };
}
