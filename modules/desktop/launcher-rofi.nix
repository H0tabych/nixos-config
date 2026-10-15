# Фича: launcher-rofi · Слот: launcher · Домен: desktop · Классы: H · Для: capability desktop
# Контракт: SLOT-4. Launcher не держит постоянного процесса (запускается по
# требованию из конфига композитора — DESK-3), пункт «демон — user-юнит» не
# применяется. Конфиг rofi — в dotfiles (DOT-3), сюда не входит.
# rofi-emoji (DSN-S5, R6.8, исправление): dotfiles/rofi/config.rasi включает
# режим emoji (modi), но сам modi — отдельный плагин (ПРОВЕРЕНО: `rofi -show
# drun` падал с "Mode emoji is not found", на машине 2026-10-15). Плагин — не
# соседний пакет в профиле (его .so лежит в другом store-пути, rofi туда не
# заглядывает), а pkgs.rofi.override { plugins = […]; } (ПРОВЕРЕНО по исходнику
# nixpkgs, pkgs/by-name/ro/rofi): сборка добавляет самой rofi обёртку
# `-plugin-path $out/lib/rofi`, включающую .so плагина.
# Зависимости: —
_: {
  flake.modules.homeManager.launcher-rofi =
    { pkgs, ... }:
    {
      home.packages = [ (pkgs.rofi.override { plugins = [ pkgs.rofi-emoji ]; }) ];
    };
}
