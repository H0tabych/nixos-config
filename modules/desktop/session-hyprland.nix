# Фича: session-hyprland · Слот: session · Домен: desktop · Классы: N · Для: capability desktop
# Контракт: слот session (ARCHITECTURE.md §6, контракт ключевых слотов), DESK-1, DESK-2.
# Композитор запускается через менеджер сессий (UWSM), а не через встроенную
# systemd-интеграцию HM (HM-модуль Hyprland не используется, A.6) — единственный
# механизм интеграции сессии. `programs.hyprland.withUWSM` включает `programs.uwsm`;
# `waylandCompositors.hyprland` регистрирует desktop-файл UWSM-сессии для
# display-manager. ПРОВЕРИТЬ: SDDM наряду с ним покажет и обычную запись Hyprland
# (её добавляет сам модуль hyprland безусловно) — выбирать запись с (UWSM) вручную,
# пока не решено, стоит ли её принудительно скрывать.
# Зависимости: display-manager (сессия должна быть предложена менеджером входа).
_: {
  flake.modules.nixos.session-hyprland = {
    programs.hyprland = {
      enable = true;
      withUWSM = true;
    };

    programs.uwsm.waylandCompositors.hyprland = {
      prettyName = "Hyprland";
      comment = "Hyprland, запущенный через UWSM (DESK-2)";
      binPath = "/run/current-system/sw/bin/Hyprland";
    };
  };
}
