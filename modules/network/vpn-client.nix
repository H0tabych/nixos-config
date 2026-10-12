# Фича: vpn-client · Слот: — · Домен: network · Классы: N · Для: хоста с корпоративным VPN
# Контракт: ARCHITECTURE.md §6 — network («корпоративные/штатные VPN»), VPN-INT-5.
# Весь .ovpn-профиль (сертификаты, ключи, auth) — один секрет sops; в Nix-конфиге
# и /nix/store — только путь к нему через директиву OpenVPN `config <file>`
# (принцип VPN-CLI-2: в store попадают лишь плейсхолдеры). DNS от сервера VPN
# (updateResolvConf) не включается — её владелец network-manager/dns-resolver,
# не эта фича (ARCH-1). VPN-INT-5 («поверх туннеля по умолчанию») требует
# прозрачной маршрутизации режима M2 (R5.4); до него трафик идёт напрямую —
# задокументированное отступление для M1.
# Зависимости: host-facts (my.host.name, через config.my.* — ARCH-3).
{ config, ... }:
let
  secretsFile = config.flake.lib.repo.secrets;
in
{
  flake.modules.nixos.vpn-client =
    { config, ... }:
    {
      sops.secrets."vpnClient.config" = {
        sopsFile = secretsFile "hosts/${config.my.host.name}.yaml";
        restartUnits = [ "openvpn-corporate.service" ];
      };

      services.openvpn.servers.corporate = {
        config = "config ${config.sops.secrets."vpnClient.config".path}";
        autoStart = false;
      };
    };
}
