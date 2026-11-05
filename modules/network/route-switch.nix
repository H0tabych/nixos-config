# Фича: route-switch · Слот: — · Домен: network · Классы: N · Для: хоста с пресетом tunnel
# Контракт: NET-13, ADR-40, VPN-MOD-9, VPN-MOD-10, VPN-A16. Маршрут туннеля во время
# работы: tunnel (catch-all → выход) или direct (catch-all → напрямую). Владеет
# состоянием, переключателем и правилом авторизации; конфиги и выбор между ними при
# старте — у реализации слота (tunnel-<р>), которая вкладывает свой юнит в
# my.tunnel.route.restartUnits (опция-интерфейс объявлена в tunnel-facts, ADR-34).
#
# Состояние — файл в tmpfs (my.tunnel.route.stateFile): переживает активацию и
# гибернацию, после перезагрузки его нет, то есть маршрут tunnel. Автоматического
# перехода в direct нет ни по таймеру, ни по отказу выхода (VPN-MOD-10).
#
# Авторизация: управление юнитами переключателя — auth_admin БЕЗ удержания. Штатное
# auth_admin_keep удерживало бы разрешение, а песочница агентов достаёт до системной
# шины: подтверждение должно спрашиваться при каждом переключении в обе стороны. На
# хосте без polkit правило не создаётся и переключает только root.
#
# Интерфейс для dotfiles (SLOT-3, DOT-5): юнит route-switch@<маршрут>.service, файл
# состояния и machine.d/tunnel-env с путём к нему и списком юнитов клиента.
# Зависимости: tunnel-facts (my.tunnel.route.*) — только чтение (ARCH-3).
_: {
  flake.modules.nixos.route-switch =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.my.tunnel.route;
      stateDir = builtins.dirOf cfg.stateFile;
      restartCmd = lib.optionalString (
        cfg.restartUnits != [ ]
      ) "systemctl restart ${lib.escapeShellArgs cfg.restartUnits}";

      # Значение проверяется здесь, а не только правилом polkit: root и прямой вызов
      # скрипта тоже не должны записать мусор. Запись атомарна (временный файл + mv),
      # параллельные переключения — под flock. Вывод попадает в журнал юнита.
      switchScript = pkgs.writeShellScript "route-switch" ''
        set -eu
        route="$1"
        case "$route" in
          tunnel | direct) ;;
          *)
            echo "route-switch: неизвестный маршрут '$route'" >&2
            exit 2
            ;;
        esac
        exec 9>"${stateDir}/.lock"
        flock 9
        tmp="$(mktemp "${stateDir}/.route.XXXXXX")"
        printf '%s\n' "$route" > "$tmp"
        chmod 0644 "$tmp"
        mv -f "$tmp" "${cfg.stateFile}"
        echo "route-switch: маршрут → $route"
        ${restartCmd}
        echo "route-switch: клиент перезапущен, маршрут $route"
      '';
    in
    {
      systemd.tmpfiles.rules = [
        "d ${stateDir} 0755 root root - -"
      ]
      ++ lib.concatMap (user: [
        "L+ /home/${user}/.config/machine.d/tunnel-env - - - - ${pkgs.writeText "tunnel-env" ''
          # Сгенерировано Nix (route-switch, NET-13) — не редактируйте руками.
          export TUNNEL_ROUTE_STATE="${cfg.stateFile}"
          export TUNNEL_ROUTE_UNITS="${lib.concatStringsSep " " cfg.restartUnits}"
        ''}"
      ]) config.my.host.users;

      systemd.services."route-switch@" = {
        description = "Переключение маршрута туннеля: %i (NET-13)";
        path = [
          pkgs.coreutils
          pkgs.util-linux
          pkgs.systemd
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${switchScript} %i";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ stateDir ];
        };
      };

      security.polkit.extraConfig = lib.mkIf config.security.polkit.enable ''
        polkit.addRule(function(action, subject) {
          var unit = action.lookup("unit");
          if (action.id == "org.freedesktop.systemd1.manage-units" && unit &&
              /^route-switch@(tunnel|direct)\.service$/.test(unit)) {
            return polkit.Result.AUTH_ADMIN;
          }
        });
      '';
    };
}
