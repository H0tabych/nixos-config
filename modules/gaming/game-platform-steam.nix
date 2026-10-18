# Фича: game-platform-steam · Слот: game-platform · Домен: gaming · Классы: N · Для: capability gaming
# Контракт: A.3 (слот game-platform → Steam). DSN-EXC-2/DSN-EXC-7: клиент не
# темизируется, исключение подтверждается в hypr/hyprland.lua (dotfiles,
# правило solid-steam) — не здесь.
# Зависимости: —
_: {
  flake.modules.nixos.game-platform-steam = {
    programs.steam.enable = true;
  };
}
