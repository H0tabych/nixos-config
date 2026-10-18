# Фича: mail-calendar-thunderbird · Слот: mail-calendar · Домен: office · Классы: H · Для: capability office
# Контракт: слот mail-calendar (ARCHITECTURE.md §6, Приложение A.3). Thunderbird
# включает календарь (Lightning) штатно — отдельный пакет не нужен. Конфиг
# приложения — вне реестра dotfiles (DOT-2): профиль Thunderbird не текстовый
# файл для переноса; тема — из системного GTK (theme.nix, R6.6).
# Зависимости: —
_: {
  flake.modules.homeManager.mail-calendar-thunderbird = { pkgs, ... }: {
    home.packages = [ pkgs.thunderbird ];
  };
}
