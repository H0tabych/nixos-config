# Фича: file-manager-yazi · Слот: file-manager · Домен: shell · Классы: H · Для: capability desktop
# Контракт: слот file-manager (ARCHITECTURE.md §6, контракт ключевых слотов):
# пакет; конфиг — dotfiles (DOT-3), цвета — из палитры. HM-модуль programs.yazi
# не используется — он собирает settings/initLua/plugins в пакет через override
# (генератор, DOT-3 для приложения реестра).
# Зависимости: —
_: {
  flake.modules.homeManager.file-manager-yazi = { pkgs, ... }: { home.packages = [ pkgs.yazi ]; };
}
