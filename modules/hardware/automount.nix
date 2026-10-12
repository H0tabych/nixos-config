# Фича: automount · Слот: — · Домен: hardware · Классы: N · Для: всех хостов
# Контракт: — (автомонтирование съёмных носителей, ARCHITECTURE.md §6 — hardware).
# ntfs3g — в PATH ради mount.ntfs/mount.ntfs-3g: udisks2 выбирает его вместо
# ядрового ntfs3, который на проверенном носителе не монтировался на запись.
# Зависимости: —
_: {
  flake.modules.nixos.automount =
    { pkgs, ... }:
    {
      services.udisks2.enable = true;
      services.gvfs.enable = true;
      environment.systemPackages = [ pkgs.ntfs3g ];
    };
}
