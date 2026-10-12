# Фича: automount · Слот: — · Домен: hardware · Классы: N · Для: всех хостов
# Контракт: — (автомонтирование съёмных носителей, ARCHITECTURE.md §6 — hardware).
# NTFS включается через boot.supportedFilesystems: эта опция добавляет ntfs3g в
# system.fsPackages, то есть mount.ntfs/mount.ntfs-3g появляются там, где их ищет
# udisks2, и одновременно готовит initrd. Прежний вариант (ntfs3g в
# environment.systemPackages) работал, но тащил весь пакет в системный PATH ради
# двух mount-хелперов — штатная опция выражает ту же нужду точнее (ARCH-11).
# Ядровый ntfs3 на проверенном носителе не монтировался на запись, поэтому нужен
# именно ntfs3g.
# Зависимости: —
_: {
  flake.modules.nixos.automount = _: {
    services.udisks2.enable = true;
    services.gvfs.enable = true;
    boot.supportedFilesystems.ntfs = true;
  };
}
