# Фича: dns-resolver · Слот: — · Домен: network · Классы: N · Для: хостов с туннелем
# Контракт: VPN-DNS-2 (единственный upstream = точка входа DNS клиента туннеля,
# DNS из DHCP игнорируется), VPN-DNS-1 (класс `scoped`), VPN-DNS-6 (при
# недоступном туннеле — быстрый отказ, откат на DNS провайдера запрещён),
# VPN-DNS-4 (IPv6 по политике). Единственный владелец системного резолвера
# (ADR-34): фичи не пишут resolv.conf сами, а вкладываются в
# my.tunnel.dns.scopedZones.
#
# Почему systemd-resolved. Нужен резолвер, умеющий адресовать запрос по зоне на
# конкретный сервер через конкретный линк — это ровно его domain-routing
# (`Domains=~зона` на линке). Плоский resolv.conf этого не выражает, а именно
# из-за него возникло D6.
#
# Два независимых контура (ADR-37, дефект D8):
#   1. Класс `scoped` — включается, когда владелец линка вложил зоны, НЕЗАВИСИМО
#      от my.tunnel.mode. Корпоративный split-horizon — свойство активного
#      vpn-client, а не режима xray-туннеля; привязка всей фичи к `mode == m2`
#      делала зоны в M1 мёртвым конфигом.
#   2. Строгая политика upstream (VPN-DNS-2, VPN-DNS-6, VPN-DNS-7) — только M2.
#      В M1 обнуление upstream отрезало бы DNS целиком, поэтому там глобальный
#      резолвер остаётся штатным (адреса из DHCP через network-manager), а
#      scoped-зоны ложатся поверх него.
# Зависимости: tunnel-facts (my.tunnel.*) — только чтение (ARCH-3);
# network-manager не должен навязывать DNS в M2 (§2.6) — обеспечено ниже.
_: {
  flake.modules.nixos.dns-resolver =
    { config, lib, ... }:
    let
      cfg = config.my.tunnel;
      m2 = cfg.mode == "m2";

      scoped = cfg.dns.scopedZones;
      links = lib.unique (map (z: z.link) scoped);

      # Имя линка в опциях systemd-resolved задаётся через per-link настройки,
      # а применяется утилитой resolvectl: линк туннеля появляется в рантайме,
      # поэтому декларативного networkd-файла для него нет.
      #
      # Все записи одного линка применяются одной командой: resolvectl dns и
      # resolvectl domain заменяют список целиком, а не дополняют его, поэтому
      # вызов на запись затирал бы предыдущую.
      applyLink =
        link:
        let
          entries = lib.filter (z: z.link == link) scoped;
          servers = lib.concatMapStringsSep " " (z: z.server) entries;
          # `~зона` — routing-only domain: на этот линк уходят запросы ТОЛЬКО
          # для перечисленных зон, а не весь прочий трафик (иначе корпоративный
          # резолвер увидел бы личные запросы — причина D6).
          domains = lib.concatMapStringsSep " " (
            z: lib.concatMapStringsSep " " (zone: "~${zone}") z.zones
          ) entries;
        in
        ''
          resolvectl dns ${link} ${servers}
          resolvectl domain ${link} ${domains}
          # Запросы вне зон на этот линк не уходят.
          resolvectl default-route ${link} false
        '';

      # По юниту на линк: каждый привязан к появлению своего устройства.
      scopedUnits = lib.listToAttrs (
        map (
          link:
          lib.nameValuePair "dns-resolver-scoped-${link}" {
            description = "Адресация scoped-зон на линке ${link} (VPN-DNS-1)";

            # Юнит висит на ПОЯВЛЕНИИ линка, а не на multi-user.target. Линк
            # туннеля поднимается позже загрузки (у vpn-client autoStart = false,
            # туннель включают вручную), поэтому oneshot на multi-user.target
            # отрабатывал в пустоту, а с RemainAfterExit = true больше не
            # запускался — зоны не применялись никогда.
            #
            # Имя device-юнита выводится из поля link в данных политики, а не из
            # имени юнита чужой фичи, поэтому ARCH-3 не нарушается: dns-resolver
            # по-прежнему не знает, кто именно поднимает линк.
            bindsTo = [ "sys-subsystem-net-devices-${link}.device" ];
            wantedBy = [ "sys-subsystem-net-devices-${link}.device" ];
            after = [
              "sys-subsystem-net-devices-${link}.device"
              "systemd-resolved.service"
            ];
            requires = [ "systemd-resolved.service" ];

            # resolvectl — из systemd; отдельной опции services.resolved.package нет.
            path = [ config.systemd.package ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            # Проверки существования линка нет намеренно: BindsTo гарантирует,
            # что юнит запускается только при живом устройстве и гаснет с ним.
            script = applyLink link;
          }
        ) links
      );
    in
    lib.mkMerge [
      # Системным резолвером становимся в обоих контурах: и для scoped-зон, и
      # для строгой политики M2 — без resolved ни то, ни другое невыразимо.
      (lib.mkIf (m2 || scoped != [ ]) {
        # API 26.05 — settings.Resolve.*; extraConfig в этом релизе удалён
        # (mkRemovedOptionModule), поэтому только так.
        services.resolved = {
          enable = true;

          settings.Resolve = {
            DNSStubListener = "yes";
            # Корпоративный split-horizon не проходит валидацию: внутренние зоны
            # подписаны не так, как их публичные тёзки.
            DNSSEC = false;
          };
        };
      })

      # Контур 1 — класс `scoped` (VPN-DNS-1), независимо от режима (ADR-37).
      (lib.mkIf (scoped != [ ]) {
        assertions = [
          {
            assertion = lib.all (z: z.link != "") scoped;
            message = "dns-resolver: в my.tunnel.dns.scopedZones пустой link — по VPN-DNS-1 это отказ, зону некуда адресовать";
          }
        ];

        systemd.services = scopedUnits;
      })

      # Контур 2 — строгая политика upstream, только M2.
      (lib.mkIf m2 {
        services.resolved.settings.Resolve = {
          # VPN-DNS-2: единственный upstream — точка входа DNS клиента туннеля.
          # ПРОВЕРИТЬ: её адрес появляется вместе с M2-частью tunnel-xray
          # (dns-out/tun-in, P.3). Пока список пуст, глобальных запросов резолвер
          # не обслуживает и отвечает отказом — это поведение VPN-DNS-6
          # (быстрый отказ), а не утечка к провайдеру.
          DNS = [ ];

          # VPN-DNS-6: откат на DNS провайдера запрещён — резервных нет.
          FallbackDNS = [ ];

          # VPN-DNS-7: кэш держит клиент туннеля; второй кэш здесь не нужен.
          Cache = "no";
        };

        # VPN-DNS-2: DNS, выданный DHCP, игнорируется — менеджер сети его не
        # навязывает. Владелец механизма резолвера здесь, поэтому параметр
        # выставляется отсюда (ADR-34), а не в network-manager.
        # networking.resolvconf.enable модуль resolved выключает сам — здесь
        # не дублируется (ARCH-5).
        #
        # ARCH-13 (обоснование mkForce): модуль resolved в nixpkgs безусловно
        # ставит networkmanager.dns = "systemd-resolved", то есть NM отдаёт
        # резолверу адреса DNS из DHCP как per-link серверы. В M2 это ровно та
        # утечка, которую запрещает VPN-DNS-2, поэтому значение перебивается на
        # "none": ни один адрес из DHCP до резолвера не доходит. Глобальный
        # upstream — точка входа клиента туннеля, scoped-зоны ставит контур 1.
        # В M1 это значение намеренно НЕ перебивается: там адреса из DHCP и есть
        # штатный глобальный резолвер.
        networking.networkmanager.dns = lib.mkForce "none";
      })
    ];
}
