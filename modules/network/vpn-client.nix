# Фича: vpn-client · Слот: — · Домен: network · Классы: N · Для: хоста с корпоративным VPN
# Контракт: ARCHITECTURE.md §6 — network («корпоративные/штатные VPN»), VPN-INT-5.
# Структура .ovpn-профиля (сервер, порт, протокол — публичные данные провайдера,
# SEC-2 класс C, не секрет) — плейн-файл assets/vpn-client/<хост>.ovpn, путь
# через lib.repo.assets (STR-9); его содержимое попадает в /nix/store как есть —
# это нормально для публичных данных, не для секрета (R4.12: правка R4.8).
# Секрет — только логин и пароль (SEC-2 класс A): services.openvpn ...authUserPass
# принимает путь к файлу (NixOS-опция openvpn.servers.<n>.authUserPass как строка,
# не атрибут username/password — тот кладёт значения в стор), путь — из sops
# (принцип SEC-4: в /nix/store — только путь, не значение). DNS от сервера VPN
# (updateResolvConf) не включается — её владелец network-manager/dns-resolver,
# не эта фича (ARCH-1). VPN-INT-5 («поверх туннеля по умолчанию») — цель M2
# (R5.4), до него трафик OpenVPN идёт напрямую — задокументированное отступление
# для M1.
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
    };
}
