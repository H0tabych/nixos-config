# Фича: launcher-rofi · Слот: launcher · Домен: desktop · Классы: H · Для: capability desktop
# Контракт: SLOT-4. Launcher не держит постоянного процесса (запускается по
# требованию из конфига композитора — DESK-3), пункт «демон — user-юнит» не
# применяется. Конфиг rofi — в dotfiles (DOT-3), сюда не входит.
# Зависимости: —
_: {
  flake.modules.homeManager.launcher-rofi = { pkgs, ... }: { home.packages = [ pkgs.rofi ]; };
}
