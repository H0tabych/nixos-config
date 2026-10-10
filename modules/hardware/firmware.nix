# Фича: firmware · Слот: — · Домен: hardware · Классы: N · Для: всех хостов
# Контракт: — (загрузка бинарных прошивок устройств, ARCHITECTURE.md §6 — hardware).
# Зависимости: —
_: {
  flake.modules.nixos.firmware = _: {
    # enableAllFirmware тащит facetimehd-*/broadcom-bt/xone-dongle — не наше
    # железо, и facetimehd-calibration качается напрямую с download.info.apple.com
    # (FOD без сети не собирается). enableRedistributableFirmware даёт
    # linux-firmware и нужные wifi/bt/audio-прошивки без этого.
    hardware.enableRedistributableFirmware = true;
    hardware.wirelessRegulatoryDatabase = true;
  };
}
