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
# В M1 фича не активна: там DNS идёт прокси-осведомлёнными приложениями
# (VPN-DNS-5), системный резолвер остаётся штатным, и навязывать заглушку
# незачем. Переключение — одним параметром my.tunnel.mode (откат R5.4).
# Зависимости: tunnel-facts (my.tunnel.*) — только чтение (ARCH-3);
# network-manager не должен навязывать DNS (§2.6) — обеспечено ниже.
_: {
  flake.modules.nixos.dns-resolver =
    { config, lib, ... }:
    let
      cfg = config.my.tunnel;
      m2 = cfg.mode == "m2";

      scoped = cfg.dns.scopedZones;

      # Имя линка в опциях systemd-resolved задаётся через per-link настройки,
      # а применяется утилитой resolvectl: линк туннеля появляется в рантайме,
      # поэтому декларативного networkd-файла для него нет.
      applyScoped = lib.concatMapStringsSep "\n" (
        z:
        let
          # `~зона` — routing-only domain: на этот линк уходят запросы ТОЛЬКО
          # для перечисленных зон, а не весь прочий трафик (иначе корпоративный
          # резолвер увидел бы личные запросы — причина D6).
          domains = lib.concatMapStringsSep " " (zone: "~${zone}") z.zones;
        in
        ''
          if [ -d /sys/class/net/${z.link} ]; then
            resolvectl dns ${z.link} ${z.server}
            resolvectl domain ${z.link} ${domains}
            # Запросы вне зон на этот линк не уходят.
            resolvectl default-route ${z.link} false
          fi
        ''
      ) scoped;
    in
    lib.mkIf m2 {
      assertions = [
        {
          assertion = lib.all (z: z.link != "") scoped;
          message = "dns-resolver: в my.tunnel.dns.scopedZones пустой link — по VPN-DNS-1 это отказ, зону некуда адресовать";
        }
      ];

      # API 26.05 — settings.Resolve.*; extraConfig в этом релизе удалён
      # (mkRemovedOptionModule), поэтому только так.
      services.resolved = {
        enable = true;

        settings.Resolve = {
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
          DNSStubListener = "yes";
          DNSSEC = false;
        };
      };

      # VPN-DNS-2: DNS, выданный DHCP, игнорируется — менеджер сети его не
      # навязывает. Владелец механизма резолвера здесь, поэтому параметр
      # выставляется отсюда (ADR-34), а не в network-manager.
      # networking.resolvconf.enable модуль resolved выключает сам — здесь
      # не дублируется (ARCH-5).
      #
      # ARCH-13 (обоснование mkForce): модуль resolved в nixpkgs безусловно
      # ставит networkmanager.dns = "systemd-resolved", то есть NM отдаёт
      # резолверу адреса DNS из DHCP как per-link серверы. Это ровно та утечка,
      # которую запрещает VPN-DNS-2, поэтому значение перебивается на "none":
      # ни один адрес из DHCP до резолвера не доходит. Глобальный upstream —
      # точка входа клиента туннеля, scoped-зоны ставит юнит ниже; больше
      # источников DNS у системы нет.
      networking.networkmanager.dns = lib.mkForce "none";

      systemd.services.dns-resolver-scoped = lib.mkIf (scoped != [ ]) {
        description = "Адресация scoped-зон по линкам (VPN-DNS-1)";
        after = [ "systemd-resolved.service" ];
        requires = [ "systemd-resolved.service" ];
        wantedBy = [ "multi-user.target" ];
        # resolvectl — из systemd; отдельной опции services.resolved.package нет.
        path = [ config.systemd.package ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = applyScoped;
      };
    };
}
