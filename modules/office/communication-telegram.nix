# Фича: communication-telegram · Слот: communication · Домен: office · Классы: H · Для: capability office
# Контракт: DOT-2 — приложение вне реестра dotfiles конфигурируется Nix; у
# Telegram нет унаследованного конфига для переноса (A.3: office-suite /
# mail-calendar / documents / communication → ... / Telegram), поэтому фича
# ограничена установкой пакета.
# Зависимости: —
_: {
  flake.modules.homeManager.communication-telegram = { pkgs, ... }: {
    home.packages = [ pkgs.telegram-desktop ];
  };
}
