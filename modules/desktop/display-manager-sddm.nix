# Фича: display-manager-sddm · Слот: display-manager · Домен: desktop · Классы: N · Для: capability desktop
# Контракт: слот display-manager (ARCHITECTURE.md §6, контракт ключевых слотов).
# Предлагает сессии установленных session-<р> (сейчас — session-hyprland);
# тема из палитры — ПРОВЕРИТЬ, конкретная тема SDDM не выбрана (DESK-6).
# Зависимости: —
_: {
  flake.modules.nixos.display-manager-sddm = {
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };
  };
}
