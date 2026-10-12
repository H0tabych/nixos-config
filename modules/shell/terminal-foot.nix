# Фича: terminal-foot · Слот: terminal · Домен: shell · Классы: H · Для: capability desktop
# Контракт: слот terminal (ARCHITECTURE.md §6, контракт ключевых слотов): пакет;
# конфиг — dotfiles (DOT-3), цвета — из палитры. HM-модуль programs.foot не
# используется — он пишет /etc/xdg/foot/foot.ini даже с пустыми settings
# (генератор, DOT-3 для приложения реестра).
# Зависимости: —
_: {
  flake.modules.homeManager.terminal-foot = { pkgs, ... }: { home.packages = [ pkgs.foot ]; };
}
