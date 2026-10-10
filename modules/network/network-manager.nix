# Фича: network-manager · Слот: — · Домен: network · Классы: N · Для: всех хостов
# Контракт: — (управление сетевыми интерфейсами, ARCHITECTURE.md §6 — network).
# Зависимости: —
_: {
  flake.modules.nixos.network-manager = _: {
    networking.networkmanager.enable = true;
  };
}
