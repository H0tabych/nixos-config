# Фича: automount · Слот: — · Домен: hardware · Классы: N · Для: всех хостов
# Контракт: — (автомонтирование съёмных носителей, ARCHITECTURE.md §6 — hardware).
# Зависимости: —
_: {
  flake.modules.nixos.automount = _: {
    services.udisks2.enable = true;
    services.gvfs.enable = true;
  };
}
