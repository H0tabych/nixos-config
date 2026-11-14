# Фича: effects-profile · Слот: — · Домен: desktop · Классы: H · Для: capability desktop
# Контракт: DESK-9 — сам переключатель (symlink'и, hyprctl reload) — скрипт
# hypr/scripts/profile в dotfiles; этот юнит владеет только слежением за
# источником питания (DSN-S7, DESIGN_SYSTEM.md раздел 9, DSN-PWR-1/2) и вызовом
# переключателя с именем профиля ac/battery. Источники power_supply опрашиваются
# upower по типу устройства (`line_power_*`), а не по имени конкретного адаптера
# (ACAD и т. п.) — без констант хоста, тем же правилом, что и у самого DESK-9
# скрипта. При старте юнита (вход в сессию) профиль ставится по источнику напрямую —
# это и снимает ручной solid/game, оставленный предыдущей сессией (DSN-PWR-2:
# "снимаются при выходе из сессии").
# R9.27 (D25): `upower --monitor` сообщает о КАЖДОМ изменении устройств (процент заряда
# и т. п.), а не только о смене источника; раньше любое событие откатывало ручной
# solid/game через несколько минут. Теперь реакция — только на смену источника, и только
# если профиль автоматический (ac/battery); ручной живёт до выхода из сеанса или до
# возврата вручную (`profile toggle`, `profile auto`). Источник пишется в
# $XDG_STATE_HOME/glass-tide/power — по нему переключатель находит `auto` (DSN-PWR-7).
# Зависимости: —
_: {
  flake.modules.homeManager.effects-profile =
    { pkgs, ... }:
    let
      watch = pkgs.writeShellApplication {
        name = "effects-profile-watch";
        runtimeInputs = [
          pkgs.upower
          pkgs.coreutils
          pkgs.gnugrep
        ];
        text = ''
          profile_script="$HOME/.config/hypr/scripts/profile"
          state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/glass-tide"
          power_file="$state_dir/power"
          mkdir -p "$state_dir"

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

          last=$(detect)
          printf '%s\n' "$last" > "$power_file"
          "$profile_script" "$last"

          upower --monitor | while read -r _; do
            now=$(detect)
            [ "$now" != "$last" ] || continue
            last=$now
            printf '%s\n' "$now" > "$power_file"
            case "$("$profile_script")" in
              ac | battery) "$profile_script" "$now" ;;
            esac
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
