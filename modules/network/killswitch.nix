# Фича: killswitch · Слот: — · Домен: network · Классы: N · Для: хостов с туннелем в M2
# Контракт: VPN-KS-1..9, NET-8. Владеет собственной таблицей nftables,
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
# «линк туннеля» (класс устройств `tun*`, а не имя конкретного хоста) и
# «разрешённые линки» из политики.
# VPN-KS-8 — таблица не привязана к юниту клиента: при его остановке и при
# suspend/hibernate правила остаются, окна без правил нет.
# VPN-KS-9 — восстановление: консоль и откал поколения доступны всегда, правила
# не трогают входящий трафик и loopback (процедуры KS-6/KS-9 — runbook/tunnel.md).
#
# В M1 фича не активна: VPN-KS-1 делает kill switch обязательным именно в M2, а
# в M1 трафик идёт напрямую — отказ по умолчанию отрезал бы сеть целиком.
# Откат режима — один параметр my.tunnel.mode.
# Зависимости: tunnel-facts (my.tunnel.*) — только чтение (ARCH-3).
_: {
  flake.modules.nixos.killswitch =
    { config, lib, ... }:
    let
      cfg = config.my.tunnel;

      allowed = cfg.killswitch.allowedInterfaces;
      allowedRule =
        lib.optionalString (allowed != [ ])
          "oifname { ${lib.concatMapStringsSep ", " (i: ''"${i}"'') allowed} } accept";

      ipv6Blocked = cfg.ipv6 == "blocked";

      reject = "reject with icmpx type admin-prohibited";
    in
    lib.mkIf (cfg.mode == "m2") {
      networking.nftables = {
        enable = true;

        # Имя таблицы фиксировано: процедура KS-6 (временное снятие на время
        # портала авторизации) должна работать с предсказуемым объектом.
        tables.killswitch = {
          family = "inet";
          content = ''
            chain output {
              type filter hook output priority filter; policy drop;

              # Уже установленные соединения — чтобы правила, применённые на
              # ходу, не рвали текущие сессии (KS-9).
              ct state established,related accept

              oifname "lo" accept

              # Линк туннеля как роль, а не имя хоста (KS-7): tun* — класс
              # устройств, одинаковый на любом хосте.
              oifname "tun*" accept

              ${allowedRule}

              # KS-2: сам клиент туннеля — по метке.
              meta mark ${toString cfg.killswitch.mark} accept

              # Служебный трафик локальной сети: DHCP и обнаружение.
              udp dport { 67, 68 } accept

              # KS-5: DNS и DoT мимо туннеля режутся ДО общего разрешения
              # локальной сети — иначе запросы утекают через домашний
              # маршрутизатор. Порядок правил здесь и есть смысл KS-5.
              meta l4proto { tcp, udp } th dport 53 ${reject}
              tcp dport 853 ${reject}

              # Локальная сеть (после запрета DNS выше): принтеры, NAS,
              # локальный инференс (VPN-RTE-4) — не через туннель никогда.
              ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 } accept
              ip6 daddr { fe80::/10, fc00::/7 } accept

              ${lib.optionalString ipv6Blocked ''
                # VPN-DNS-4: исходящий IPv6 вне туннеля — отказом, не молча.
                meta nfproto ipv6 ${reject}
              ''}

              # KS-3: прочее — отказ, не тишина.
              ${reject}
            }

            # KS-4: пересылаемый трафик (контейнеры, виртуальные мосты) покрыт
            # тем же правилом.
            chain forward {
              type filter hook forward priority filter; policy drop;

              ct state established,related accept
              oifname "tun*" accept
              ${allowedRule}
              meta l4proto { tcp, udp } th dport 53 ${reject}
              ${reject}
            }
          '';
        };
      };
    };
}
