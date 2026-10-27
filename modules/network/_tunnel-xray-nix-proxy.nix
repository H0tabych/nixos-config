# Приватная часть владельца: tunnel-xray · Домен: network
# Контракт: ADR-39 — временное исключение из NET-10/VPN-MOD-4 («прокси-
# переменные M1 в одном месте»): nix-daemon не входит в процессы, читающие
# прокси-переменные (NET-7), и в M1 не покрыт ничем; измеренный отказ —
# docs/adr/ADR-039-nix-daemon-m1-proxy.md, не гипотеза. Снимается вместе с
# переходом на M2 (гейт 7.3) — тогда этот файл и его импорт в tunnel-xray.nix
# удаляются целиком (условие снятия — в ADR). Секретов нет: адрес и порт —
# те же публичные loopback-значения, что уже в my.tunnel.local (SEC-2).
# Импортируется и упоминается только в tunnel-xray.nix (C8).
# Зависимости: —
{ lib }:
{
  # address/port/noProxy приходят от владельца (my.tunnel.local) — здесь не
  # дублируются (как и mkRoutesService у соседней приватной части).
  mkEnv =
    {
      address,
      port,
      noProxy,
    }:
    let
      httpProxy = "http://${address}:${toString port}";
    in
    {
      http_proxy = httpProxy;
      https_proxy = httpProxy;
      no_proxy = lib.concatStringsSep "," noProxy;
    };
}
