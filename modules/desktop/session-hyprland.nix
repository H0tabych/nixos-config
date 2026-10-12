# Фича: session-hyprland · Слот: session · Домен: desktop · Классы: N · Для: capability desktop
# Контракт: слот session (ARCHITECTURE.md §6, контракт ключевых слотов), DESK-1, DESK-2,
# DOT-7, SLOT-1. Композитор запускается через менеджер сессий (UWSM), а не через
# встроенную systemd-интеграцию HM (HM-модуль Hyprland не используется, A.6) —
# единственный механизм интеграции сессии. `programs.hyprland.withUWSM` включает
# `programs.uwsm` (его юниты, порталы, dbus-broker).
# Регистрацию сессии у менеджера входа держит эта фича (SLOT-1): ровно одна запись,
# и только через UWSM. `programs.uwsm.waylandCompositors` не используется — он
# добавляет свою запись *вдобавок* к записи без UWSM, которую `programs.hyprland`
# ставит безусловно и отключить опцией нельзя. Сессия без UWSM — это второй
# механизм запуска (DESK-2): в ней не читается env-файл (нет прокси-переменных M1,
# VPN-A4) и не поднимается graphical-session.target UWSM, то есть не стартуют
# bar/notifier/wallpaper/clipboard/polkit-agent/osd (DESK-3, A4).
# Переменные окружения графической сессии — один механизм, env-файл UWSM
# (DOT-7, NET-10): UWSM читает `uwsm/env` из каждого каталога
# $XDG_CONFIG_HOME:$XDG_CONFIG_DIRS:$XDG_DATA_DIRS, а на NixOS /etc/xdg —
# первый элемент XDG_CONFIG_DIRS. Значения прокси берутся из my.tunnel.* и
# принадлежат tunnel-facts; здесь только доставка (ARCH-3 — через config.my.*).
# Чтение my.tunnel защищено проверкой наличия: пресет desktop должен собираться
# и на хосте без пресета tunnel.
# Зависимости: display-manager (сессия должна быть предложена менеджером входа);
# tunnel-facts (my.tunnel.*, опционально).
_: {
  flake.modules.nixos.session-hyprland =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # ARCH-13: mkForce — единственный способ снять определение
      # services.displayManager.sessionPackages, которое programs.hyprland даёт
      # безусловно (запись без UWSM). Фильтром этого не сделать: чтение
      # собственной опции замкнуло бы вычисление на себя.
      uwsmSession = pkgs.writeTextFile {
        name = "hyprland-uwsm-session";
        destination = "/share/wayland-sessions/hyprland-uwsm.desktop";
        text = ''
          [Desktop Entry]
          Name=Hyprland (UWSM)
          Comment=Hyprland, запущенный через UWSM (DESK-2)
          Exec=${lib.getExe config.programs.uwsm.package} start -F -- /run/current-system/sw/bin/Hyprland
          Type=Application
        '';
        derivationArgs.passthru.providedSessions = [ "hyprland-uwsm" ];
      };

      tunnel = config.my.tunnel;
      httpProxyUrl = "http://${tunnel.local.http.address}:${toString tunnel.local.http.port}";
      socksProxyUrl = "socks5h://${tunnel.local.socks.address}:${toString tunnel.local.socks.port}";
      noProxyStr = lib.concatStringsSep "," tunnel.local.noProxy;
      proxyMode = (config.my ? tunnel) && tunnel.mode == "m1";
    in
    {
      programs.hyprland = {
        enable = true;
        withUWSM = true;
      };

      services.displayManager.sessionPackages = lib.mkForce [ uwsmSession ];

      environment.etc."xdg/uwsm/env".text = lib.mkIf proxyMode ''
        export http_proxy=${httpProxyUrl}
        export HTTP_PROXY=${httpProxyUrl}
        export https_proxy=${httpProxyUrl}
        export HTTPS_PROXY=${httpProxyUrl}
        export all_proxy=${socksProxyUrl}
        export ALL_PROXY=${socksProxyUrl}
        export no_proxy=${noProxyStr}
        export NO_PROXY=${noProxyStr}
      '';
    };
}
