# Фича: firewall · Слот: — · Домен: security · Классы: N · Для: всех хостов
# Контракт: NET-11 (default deny; порты открывают фичи, которым они нужны), VPN 2.6.
# Бэкенд — nftables в обоих режимах туннеля: на нём работают таблицы режима M2
# (killswitch, метки клиента), поэтому переключение M1↔M2 не меняет сам файрвол
# (ADR-41). Docker идёт через iptables-nft и с этим совместим; flushRuleset остаётся
# false, так что перезагрузка правил не стирает его таблицы.
# Зависимости: —
_: {
  flake.modules.nixos.firewall = _: {
    networking.firewall.enable = true;
    networking.nftables.enable = true;
  };
}
