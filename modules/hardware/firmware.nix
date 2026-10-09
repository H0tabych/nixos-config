# Фича: firmware · Слот: — · Домен: hardware · Классы: N · Для: всех хостов
# Контракт: — (загрузка бинарных прошивок устройств, ARCHITECTURE.md §6 — hardware).
# Зависимости: —
_: {
  flake.modules.nixos.firmware = _: {
    hardware.enableAllFirmware = true;
    hardware.wirelessRegulatoryDatabase = true;
  };
}
