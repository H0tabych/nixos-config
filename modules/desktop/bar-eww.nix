# Фича: bar-eww · Слот: bar · Домен: desktop · Классы: H · Для: capability desktop
# Контракт: SLOT-4 (демон — user-юнит на graphical-session.target; значения хоста — из
# машинного слоя; внешний вид — сгенерированные токены, DSN-TOK-1), SLOT-3 (замена
# реализации слота `bar`: фича, строка в пресете и каталог dotfiles `eww/`). Заменяет
# bar-waybar (ADR-42). Конфиг панели и окна сети — в dotfiles (DOT-3), сюда не входит.
# Два юнита: `eww` — демон; `eww-bars` — окна панели по одному на монитор (скрипт
# dotfiles eww/scripts/bars слушает подключение и отключение мониторов). Оба ждут
# конфиг в ~/.config/eww (ссылку делает dotfiles-link): без него — не запускаются.
# PATH юнита (как был у waybar): минимальный PATH менеджера user-юнитов не содержит
# ни bash, ни Home-Manager профиля, а скрипты панели зовут hyprctl, nmcli, rofi,
# swayosd-client, makoctl и др. — поэтому системный и пользовательский профили;
# пакет eww — первым. Пакеты, которых нет в других фичах (jq, socat, playerctl,
# brightnessctl), ставит эта же фича. %u/%h — специфайеры systemd, не константы хоста
# (ARCH-17). Окружение Hyprland (HYPRLAND_INSTANCE_SIGNATURE, WAYLAND_DISPLAY) в
# юнит приходит из сессии (session-hyprland импортирует его в менеджер user-юнитов).
# Зависимости: —
_: {
  flake.modules.homeManager.bar-eww =
    { pkgs, lib, ... }:
    let
      path = lib.concatStringsSep ":" [
        "${pkgs.eww}/bin"
        "/run/wrappers/bin"
        "/run/current-system/sw/bin"
        "/etc/profiles/per-user/%u/bin"
        "%h/.nix-profile/bin"
        "%h/.local/state/nix/profile/bin"
        "/nix/var/nix/profiles/default/bin"
      ];
    in
    {
      home.packages = [
        pkgs.eww
        pkgs.jq
        pkgs.socat
        pkgs.playerctl
        pkgs.brightnessctl
      ];

      systemd.user.services.eww = {
        Unit = {
          Description = "Панель (eww): демон";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
          ConditionPathExists = "%h/.config/eww/eww.yuck";
        };
        Service = {
          ExecStart = "${pkgs.eww}/bin/eww daemon --no-daemonize";
          Environment = [ "PATH=${path}" ];
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      systemd.user.services.eww-bars = {
        Unit = {
          Description = "Панель (eww): окна по мониторам";
          PartOf = [ "eww.service" ];
          Requires = [ "eww.service" ];
          After = [ "eww.service" ];
          ConditionPathExists = "%h/.config/eww/scripts/bars";
        };
        Service = {
          ExecStart = "%h/.config/eww/scripts/bars";
          Environment = [ "PATH=${path}" ];
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}
