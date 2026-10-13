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
# Список устройств композитора (AQ_DRM_DEVICES, DESK-5, A5, R5.7) — тоже здесь:
# переменная специфична для aquamarine/Hyprland, поэтому её владелец — фича
# композитора, а не hardware/gpu-hybrid (тот владеет стабильными симлинками
# устройств). Так замена реализации слота остаётся правкой одной фичи (SLOT-3).
# Доставка — дропин uwsm/env.d/* (man uwsm(1)), чтобы не делить владение
# uwsm/env с прокси-переменными (ARCH-1); тексты — в приватной части (STR-6).
# Зависимости: display-manager (сессия должна быть предложена менеджером входа);
# tunnel-facts (my.tunnel.*, опционально); host-facts (my.host.gpu.*BusId) и
# gpu-hybrid (симлинки /dev/dri/by-host/*) — только чтение фактов (ARCH-3).
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
      #
      # Exec ниже вызывает start-hyprland, а не сырой бинарь Hyprland: без
      # сторожевого процесса Hyprland сам показывает оверлей "launched without
      # start-hyprland. This is highly advised against" при каждом запуске
      # (подтверждено в журнале сессии) и не перезапускается при аварийном
      # завершении.
      #
      # -D Hyprland -e: без них uwsm берёт XDG_CURRENT_DESKTOP из имени
      # команды — получилось бы "start-hyprland" вместо "Hyprland" (видно в
      # журнале: "Initial Desktop Names: start-hyprland"), и порталы/темы,
      # ищущие именно "Hyprland", перестали бы его находить. -D задаёт верное
      # имя, -e не даёт его смешать с выведенным из команды.
      uwsmSession = pkgs.writeTextFile {
        name = "hyprland-uwsm-session";
        destination = "/share/wayland-sessions/hyprland-uwsm.desktop";
        text = ''
          [Desktop Entry]
          Name=Hyprland (UWSM)
          Comment=Hyprland, запущенный через UWSM (DESK-2)
          Exec=${lib.getExe config.programs.uwsm.package} start -D Hyprland -e -F -- /run/current-system/sw/bin/start-hyprland
          Type=Application
        '';
        derivationArgs.passthru.providedSessions = [ "hyprland-uwsm" ];
      };

      # DESK-5, A5: список устройств композитора (AQ_DRM_DEVICES) динамический —
      # тексты скрипта, дропина и udev-правила вынесены в приватную часть (STR-6).
      # Механизм имеет смысл только при гибридной графике; на хосте с одной GPU
      # список не навязывается и композитор перечисляет устройства сам (откат
      # R5.7 — ровно это состояние). Пресет desktop должен собираться и там,
      # поэтому проверка факта, как и с my.tunnel ниже.
      hybridGraphics =
        config.my.host.gpu.integratedBusId != null && config.my.host.gpu.discreteBusId != null;

      compositorDevices =
        (import ./_session-hyprland-devices.nix { inherit lib pkgs; }).mkCompositorDevices
          {
            host = config.my.host;
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

      # DESK-5: список устройств композитора. Дропин uwsm/env.d/* — отдельный
      # файл, поэтому владение uwsm/env (прокси ниже) не делится (ARCH-1).
      systemd.services = lib.mkIf hybridGraphics {
        compositor-devices = compositorDevices.service;
      };
      services.udev.extraRules = lib.mkIf hybridGraphics compositorDevices.udevRules;

      # mkIf — на записи целиком, а не на её .text: запись без text и без source
      # модуль etc считает ошибкой, а не пропуском. Для прокси это важно с R5.4:
      # в режиме m2 переменные снимаются, и `.text = mkIf proxyMode …` оставил бы
      # объявленную запись uwsm/env без содержимого.
      environment.etc = lib.mkMerge [
        (lib.mkIf hybridGraphics {
          "xdg/uwsm/env.d/10-compositor-devices".text = compositorDevices.envDropIn;
        })
        (lib.mkIf proxyMode {
          "xdg/uwsm/env".text = ''
            export http_proxy=${httpProxyUrl}
            export HTTP_PROXY=${httpProxyUrl}
            export https_proxy=${httpProxyUrl}
            export HTTPS_PROXY=${httpProxyUrl}
            export all_proxy=${socksProxyUrl}
            export ALL_PROXY=${socksProxyUrl}
            export no_proxy=${noProxyStr}
            export NO_PROXY=${noProxyStr}
          '';
        })
      ];
    };
}
