# Фича: browser-firefox · Слот: browser · Домен: media · Классы: N · Для: capability media
# Контракт: APP-3 — политика браузера на уровне NixOS (не dotfiles, DOT-2,
# VPN_SUBSYSTEM.md 144-145: браузер вне реестра dotfiles). Переменные окружения
# не подходят (NET-7: не все процессы их читают) — поэтому Firefox получает
# отдельную политику Proxy через programs.firefox.policies, а не через env-файл
# менеджера сессий (единственность механизма — NET-10/DOT-7 — не нарушается:
# это другой уровень доставки для процесса, который env-файл не читает).
# В M2 политика Proxy не нужна (VPN_SUBSYSTEM.md:145) — отсутствует при
# my.tunnel.mode == "m2".
# Наличие my.tunnel проверяется явно: опции объявляет tunnel-facts из пресета
# tunnel, а эта фича живёт в пресете media. Хост с media без tunnel обязан
# собираться, иначе пресет не самодостаточен; assertions тут не помогли бы —
# обращение к необъявленной опции падает раньше их проверки.
# Зависимости: tunnel-facts (my.tunnel.*, опционально; через config.my.*,
# не import — ARCH-3).
_: {
  flake.modules.nixos.browser-firefox =
    { config, lib, ... }:
    let
      cfg = config.my.tunnel;
      # Мозилла: wildcard-домен только в виде "*.domain" (firefox-admin-docs.mozilla.org/reference/policies/proxy).
      passthroughEntry = e: if lib.hasPrefix "." e then "*${e}" else e;
      passthrough = lib.concatStringsSep ", " (map passthroughEntry cfg.local.noProxy);
      proxyMode = (config.my ? tunnel) && cfg.mode == "m1";
    in
    {
      programs.firefox = {
        enable = true;
        policies = lib.mkIf proxyMode {
          Proxy = {
            Mode = "manual";
            HTTPProxy = "${cfg.local.http.address}:${toString cfg.local.http.port}";
            SSLProxy = "${cfg.local.http.address}:${toString cfg.local.http.port}";
            SOCKSProxy = "${cfg.local.socks.address}:${toString cfg.local.socks.port}";
            SOCKSVersion = 5;
            UseProxyForDNS = true;
            Passthrough = passthrough;
            Locked = true;
          };
        };
      };
    };
}
