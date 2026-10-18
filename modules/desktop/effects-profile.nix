# Фича: effects-profile · Слот: — · Домен: desktop · Классы: H · Для: capability desktop
# Контракт: DESK-9 — сам переключатель (symlink'и, hyprctl reload) — скрипт
# hypr/scripts/profile в dotfiles; этот юнит владеет только слежением за
# источником питания (DSN-S7, DESIGN_SYSTEM.md раздел 9, DSN-PWR-1/2) и вызовом
# переключателя с именем профиля ac/battery. Источники power_supply опрашиваются
# upower по типу устройства (`line_power_*`), а не по имени конкретного адаптера
# (ACAD и т. п.) — без констант хоста, тем же правилом, что и у самого DESK-9
# скрипта. При старте юнита (вход в сессию) профиль пересчитывается напрямую,
# не через идемпотентную проверку переключателя — это и снимает ручной
# override solid/game, оставленный предыдущей сессией (DSN-PWR-2: "снимаются
# при выходе из сессии").
# Зависимости: —
_: {
  flake.modules.homeManager.effects-profile =
    { pkgs, ... }:
    let
      watch = pkgs.writeShellApplication {
        name = "effects-profile-watch";
        runtimeInputs = [ pkgs.upower ];
        text = ''
          profile_script="$HOME/.config/hypr/scripts/profile"

          detect() {
            for dev in $(upower -e); do
              case "$dev" in
                */line_power_*)
                  if upower -i "$dev" | grep -q 'online:[[:space:]]*yes'; then
                    echo ac
                    return
                  fi
                  ;;
              esac
            done
            echo battery
          }

          "$profile_script" "$(detect)"

          upower --monitor | while read -r _; do
            "$profile_script" "$(detect)"
          done
        '';
      };
    in
    {
      systemd.user.services.effects-profile = {
        Unit = {
          Description = "Автопереключение профиля эффектов Glass Tide по источнику питания (DSN-S7)";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${watch}/bin/effects-profile-watch";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}
