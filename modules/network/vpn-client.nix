# Фича: vpn-client · Слот: — · Домен: network · Классы: N · Для: хоста с корпоративным VPN
# Контракт: ARCHITECTURE.md §6 — network («корпоративные/штатные VPN»), VPN-INT-5.
# Структура .ovpn-профиля (сервер, порт, протокол — публичные данные провайдера,
# SEC-2 класс C, не секрет) — плейн-файл assets/vpn-client/<хост>.ovpn, путь
# через lib.repo.assets (STR-9); его содержимое попадает в /nix/store как есть —
# это нормально для публичных данных, не для секрета (R4.12: правка R4.8).
# Секрет — только логин и пароль (SEC-2 класс A): services.openvpn ...authUserPass
# принимает путь к файлу (NixOS-опция openvpn.servers.<n>.authUserPass как строка,
# не атрибут username/password — тот кладёт значения в стор), путь — из sops
# (принцип SEC-4: в /nix/store — только путь, не значение).
#
# DNS: сервер отдаёт split-horizon-зону. Без адресации по зонам внутренние имена
# резолвятся в публичные адреса, для которых сервер не пушит маршрут, и доступа к
# ресурсам нет — туннель поднимается, но бесполезен.
# Владелец DNS — dns-resolver (ARCH-1 в редакции ADR-34: владелец механизма ≠
# источник данных). Эта фича — **вкладчик**: она владеет линком и требует для
# него scoped-запись, но системный резолвер не пишет. Поэтому
# updateResolvConf здесь НЕ включается — а вместе с ним NixOS-модуль openvpn не
# добавляет и `script-security 2` (он появляется только при up/down/updateResolvConf),
# то есть внешние скрипты в юните не исполняются (R5.4).
# Сами зоны и адрес корпоративного резолвера — публичные данные политики класса C
# (VPN-RTE-1), задаются в хосте через my.tunnel.dns.scopedZones.
#
# VPN-INT-5 («поверх туннеля по умолчанию») — цель M2 (R5.4), до него трафик
# OpenVPN идёт напрямую — задокументированное отступление для M1.
# Зависимости: host-facts (my.host.name, через config.my.* — ARCH-3).
{ config, ... }:
let
  secretsFile = config.flake.lib.repo.secrets;
  assetsFile = config.flake.lib.repo.assets;
in
{
  flake.modules.nixos.vpn-client =
    { config, ... }:
    {
      sops.secrets."vpnClient.credentials" = {
        sopsFile = secretsFile "hosts/${config.my.host.name}.yaml";
        restartUnits = [ "openvpn-corporate.service" ];
      };

      services.openvpn.servers.corporate = {
        config = "config ${assetsFile "vpn-client/${config.my.host.name}.ovpn"}";
        authUserPass = config.sops.secrets."vpnClient.credentials".path;
        autoStart = false;
      };

      # Вкладчик, а не владелец (ADR-34): фича не настраивает DNS, но без
      # scoped-записи для её зон внутренние имена ушли бы к публичному
      # резолверу — это ровно дефект D6, поэтому отказ на сборке, а не молча.
      assertions = [
        {
          assertion = config.my.tunnel.mode != "m2" || config.my.tunnel.dns.scopedZones != [ ];
          message =
            "vpn-client в режиме m2 требует my.tunnel.dns.scopedZones для корпоративных зон "
            + "(VPN-DNS-1, класс scoped): без них split-horizon-имена уйдут к публичному резолверу";
        }
      ];

      # NixOS-модуль openvpn задаёт Restart=always без задержки. При AUTH_FAILED
      # openvpn выходит сразу, и юнит перезапускался раз в ~2.5 с — в журнале
      # 50 попыток за две минуты. Для корпоративного сервера с LDAP/AD это риск
      # блокировки учётной записи, поэтому ограничиваем темп и число попыток.
      systemd.services.openvpn-corporate = {
        startLimitIntervalSec = 600;
        startLimitBurst = 5;
        serviceConfig.RestartSec = 30;
      };
    };
}
