# Фича: hardening · Слот: — · Домен: security · Классы: N · Для: всех хостов
# Контракт: ADR-44 (граница агентов v2), AI-SBX-1 (TIOCSTI), AI-SBX-11 / R-08
# (пользовательские пространства имён MUST остаться доступными — иначе лаунчер
# агентов не стартует, а fail-closed AI-SBX-6 сделает агентов неработоспособными).
# Зависимости: —
#
# Состав намеренно минимален. НЕ добавлять без решения ADR:
#   - user.max_user_namespaces = 0 / security.allowUserNamespaces = false
#     (ломает лаунчер агентов, AI-SBX-11);
#   - security.protectKernelImage (отключает гибернацию — STO-*);
#   - security.lockKernelModules, профиль hardened (модули NVIDIA, туннель).
_: {
  flake.modules.nixos.hardening = _: {
    # TIOCSTI позволяет процессу в песочнице вставить ввод в терминал вне её.
    # Параметр закрывает это без `--new-session` у bwrap (тот ломает терминальные
    # интерфейсы агентов). На ядре ≥ 6.2 значение уже 0 (nixpkgs: LEGACY_TIOCSTI = no);
    # запись фиксирует его независимо от смены ядра.
    boot.kernel.sysctl."dev.tty.legacy_tiocsti" = 0;
  };
}
