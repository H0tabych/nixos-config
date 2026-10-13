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
# DNS: сервер отдаёт split-horizon-зону (dhcp-option DNS 10.0.1.252 +
# DOMAIN-SEARCH cs.local/controlsystems.ru/metasfera.ru). Без неё внутренние имена
# резолвятся в публичные адреса, для которых сервер не пушит маршрут, и доступа к
# ресурсам нет — туннель поднимается, но бесполезен. Поэтому updateResolvConf
# включена здесь.
# ⚠ ПРОВЕРИТЬ/РАСХОЖДЕНИЕ: по ARCH-1 владелец DNS — dns-resolver/network-manager,
# а не эта фича; перенос владения — R5.4 (VPN-INT-5). До тех пор это
# осознанное отступление: без него фича не выполняет своё назначение.
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
        updateResolvConf = true;
      };

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
