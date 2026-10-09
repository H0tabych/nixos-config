# Фича: bluetooth · Слот: — · Домен: hardware · Классы: N · Для: хостов с Bluetooth-адаптером
# Контракт: — (стек Bluetooth, ARCHITECTURE.md §6 — hardware).
# Зависимости: —
_: {
  flake.modules.nixos.bluetooth = _: {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
  };
}
