# Фича: databases · Слот: databases · Домен: dev · Классы: H · Для: capability development
# Контракт: DEV-1 (клиенты БД — глобальный минимум), слот databases
# (ARCHITECTURE.md §6, A.3): DBeaver + pgcli.
# Зависимости: —
_: {
  flake.modules.homeManager.databases = { pkgs, ... }: {
    home.packages = [
      pkgs.dbeaver-bin
      pkgs.pgcli
    ];
  };
}
