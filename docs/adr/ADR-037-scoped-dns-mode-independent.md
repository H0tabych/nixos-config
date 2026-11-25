# ADR-37: класс `scoped` (VPN-DNS-1) не зависит от `my.tunnel.mode`

- Статус: принято; закрыто на этапе 5 (ROADMAP.md D8)
- Источник: ROADMAP.md D8 (вскрыто 2026-10-14 при смене корпоративного VPN); OPS-7; VPN-DNS-1, VPN-DNS-5; ADR-34
- Решение: корпоративный split-horizon — свойство активного владельца линка (`vpn-client`), а не режима
  xray-туннеля, поэтому `dns-resolver` делится на два контура:
  - scoped-зоны включаются по непустому `my.tunnel.dns.scopedZones` в любом режиме;
  - обнуление upstream (VPN-DNS-2/6/7) и `networkmanager.dns = "none"` остаются только в M2 — в M1 они
    отрезали бы DNS целиком;
  - применение зон привязано к device-юниту линка, а не к `multi-user.target`.
- Причина: фича `dns-resolver` стояла целиком под `mkIf (mode == "m2")`, поэтому в M1 зоны
  `my.tunnel.dns.scopedZones` были мёртвым конфигом и внутренние имена корпоративного VPN не
  резолвились вовсе. Юнит `dns-resolver-scoped` висел на `multi-user.target`, а линк появляется позже
  загрузки (у `vpn-client` `autoStart = false`, туннель включают вручную): oneshot отрабатывал вхолостую
  по проверке отсутствия линка и с `RemainAfterExit = true` больше не запускался.
- Затронутые правила: VPN-DNS-1, VPN-DNS-5, OPS-7; ADR-34
