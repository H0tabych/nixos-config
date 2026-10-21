# Фича: api-tools · Слот: api-tools · Домен: dev · Классы: H · Для: capability development
# Контракт: DEV-1 (глобальный минимум разработки), слот api-tools
# (ARCHITECTURE.md §6, Приложение A.3): Postman — unfree, allowUnfree разрешён
# глобально (base/nix-settings.nix).
# Зависимости: —
_: {
  flake.modules.homeManager.api-tools = { pkgs, ... }: {
    home.packages = [ pkgs.postman ];
  };
}
