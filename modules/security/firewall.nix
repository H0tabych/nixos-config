# Фича: firewall · Слот: — · Домен: security · Классы: N · Для: всех хостов
# Контракт: NET-11 (default deny; порты открывают фичи, которым они нужны).
# Зависимости: —
_: {
  flake.modules.nixos.firewall = _: {
    networking.firewall.enable = true;
  };
}
