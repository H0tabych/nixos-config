# Фича: tunnel-xray · Слот: tunnel · Домен: network · Классы: N · Для: хоста с пресетом tunnel
# Контракт: VPN-CLI-1..9, VPN-CLI-11, VPN-MOD-2/3/4/12, NET-1..4, NET-7, NET-9, SEC-4,
# VPN-RTE-1..9, VPN-DNS-1, VPN-DNS-3..5, VPN-DNS-8, VPN-MOD-8..11, NET-13, ADR-40/41.
# Единственный владелец юнита tunnel-xray и его конфигов (VPN-CLI-1). Конфиг
# маршрута tunnel рендерится sops-nix из шаблона при активации — в /nix/store попадают
# только плейсхолдеры (VPN-CLI-2). Конфиг маршрута direct без секретов лежит в
# /nix/store; какой из двух взять — решает обёртка запуска по состоянию маршрута
# (my.tunnel.route.stateFile, им владеет route-switch).
# Пакет — из нестабильного канала (VPN-CLI-11, ARCH-14): в 26.05 версия 26.3.27, а
# выход обновляется до версии с исправлениями безопасности, и расхождение версий
# клиента и выхода — частая причина сбоев (VPN-CLI-12). Конфиг от версии не зависит,
# откат на pkgs.xray — один атрибут (ADR-41).
# Прокси-переменные графической сессии (NET-10, DOT-7) эта фича НЕ доставляет:
# env-файл менеджера сессий принадлежит слоту session (session-hyprland), иначе
# замена композитора (DESK-10) потребовала бы правки сетевой фичи (ARCH-16, SLOT-3).
# Исключение (ADR-39, временное до M2): nix-daemon.service — не часть сессии и
# не слот, подменять его при смене композитора не нужно, поэтому его прокси-
# переменные доставляет эта же фича (_tunnel-xray-nix-proxy.nix, STR-6).
# Постквантовая подпись (mldsa65Verify) не заполняется: выход её пока не
# выпускает (VPN-SRV-3 не выполнен на сервере) — это отступление, а не исключение
# по VPN-CLI-3 (ядро xray-core проверку поддерживает); запись со сроком
# пересмотра — в docs/runbook/tunnel.md.
# DNS и routing строятся из my.tunnel.policy.* данными _tunnel-xray-policy.nix
# (STR-6); domainStrategy — "IPOnDemand" в M1 (резолвит по требованию,
# VPN-RTE-3), "AsIs" в M2 (IP уже известен, домен берётся из sniffing tun-in).
# Метка sockopt.mark на всех исходящих — my.tunnel.killswitch.mark, та же, что
# killswitch.nix пропускает своим правилом (VPN-KS-2, VPN-KS-10). В M1 у процесса
# нет CAP_NET_ADMIN, поэтому setsockopt отказывает, ядро туннеля это только
# записывает в журнал info и соединение идёт дальше; метка ни на что не влияет.
# Зависимости: host-facts (my.host.name), tunnel-facts (my.tunnel.*; через
# config.my.*, не import — ARCH-3), firewall (nftables) — только assertion.
{ config, ... }:
let
  outer = config;
  secretsFile = outer.flake.lib.repo.secrets;
in
{
  flake.modules.nixos.tunnel-xray =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.my.tunnel;
      inherit (cfg) mode;
      m2 = mode == "m2";
      inherit (cfg.killswitch) mark;
      pkg = pkgs.unstable.xray;
      ph = name: config.sops.placeholder.${name};
      routes = import ./_tunnel-xray-routes.nix { inherit pkgs; };
      nixProxy = import ./_tunnel-xray-nix-proxy.nix { inherit lib; };
      policy =
        (import ./_tunnel-xray-policy.nix { inherit lib; })
        // (import ./_tunnel-xray-inbounds.nix { inherit lib; });
      configs = (import ./_tunnel-xray-config.nix { inherit lib policy; }).mkConfigs { inherit cfg ph; };

      # Маршрут direct (NET-13): секретов нет, конфиг целиком в /nix/store и не
      # зависит от ключей sops (VPN-MOD-11).
      directConfig = pkgs.writeText "tunnel-xray-direct.json" (builtins.toJSON configs.direct);

      # Credential не абсолютным путём: по systemd.exec(5) его отсутствие не фатально
      # (поиск в /run/credstore/), а клиенту в direct ключи не нужны. В tunnel без них
      # старт отклоняется ниже, как и раньше.
      credentialId = "tunnel-xray.json";

      # Выбор конфига при старте по состоянию маршрута (VPN-MOD-9): нет файла или любое
      # значение, кроме direct, — tunnel. Одна функция для проверки ядром и для запуска.
      startScript = pkgs.writeShellScript "tunnel-xray-start" ''
        route=tunnel
        [ "$(${pkgs.coreutils}/bin/cat ${cfg.route.stateFile} 2>/dev/null)" = direct ] && route=direct
        if [ "$route" = direct ]; then
          conf=${directConfig}
        else
          conf="$CREDENTIALS_DIRECTORY/${credentialId}"
          if [ ! -r "$conf" ]; then
            echo "tunnel-xray: маршрут tunnel, но конфиг с секретами не отрисован (ключи sops, VPN-MOD-11)" >&2
            exit 1
          fi
        fi
        echo "tunnel-xray: маршрут $route"
        if [ "$1" = test ]; then
          exec ${pkg}/bin/xray run -test -c "$conf"
        fi
        exec ${pkg}/bin/xray run -c "$conf"
      '';
    in
    {
      assertions = [
        {
          assertion = !m2 || config.networking.nftables.enable;
          message = "tunnel-xray в режиме m2 требует nftables (фича firewall): на них работает таблица метки клиента";
        }
      ];

      # ADR-39: исключение из NET-10/VPN-MOD-4, см. комментарий в шапке файла.
      systemd.services.nix-daemon.environment = lib.mkIf (mode == "m1") (
        nixProxy.mkEnv {
          inherit (cfg.local.http) address port;
          inherit (cfg.local) noProxy;
        }
      );

      sops.secrets = {
        "tunnel.endpoint".sopsFile = secretsFile "common.yaml";
        "tunnel.serverKey".sopsFile = secretsFile "common.yaml";
        "tunnel.serverName".sopsFile = secretsFile "common.yaml";
        "tunnel.fingerprint".sopsFile = secretsFile "common.yaml";
        "tunnel.clientId".sopsFile = secretsFile "hosts/${config.my.host.name}.yaml";
        "tunnel.shortId".sopsFile = secretsFile "hosts/${config.my.host.name}.yaml";
      };

      # Маршрут tunnel: единственный конфиг с секретами. sops-nix создаёт каталог.
      sops.templates.tunnel-xray = {
        path = "/run/credstore/${credentialId}";
        mode = "0400";
        content = builtins.toJSON configs.tunnel;
        restartUnits = [ "tunnel-xray.service" ];
      };

      # M2: обвязка со стороны ОС (см. шапку _tunnel-xray-routes.nix).
      # src_valid_mark: ядерный rp_filter должен видеть ту же восстановленную метку,
      # что и rpfilter файрвола; иначе, пока устройства нет, ответы клиента
      # проверялись бы по unreachable в таблице туннеля и отбрасывались.
      systemd.services.tunnel-routes = lib.mkIf m2 (
        routes.mkRoutesService {
          inherit (cfg) interface;
          inherit mark;
        }
      );
      networking.nftables.tables.tunnel-marks = lib.mkIf m2 (routes.mkMarksTable { inherit mark; });
      boot.kernel.sysctl = lib.mkIf m2 { "net.ipv4.conf.all.src_valid_mark" = 1; };

      # Конфиг direct публичен (секретов нет): тест tunnel-config проверяет его ядром.
      system.build.tunnelXrayDirectConfig = directConfig;

      # Юнит, который route-switch перезапускает при смене маршрута (ADR-34).
      my.tunnel.route.restartUnits = [ "tunnel-xray.service" ];

      systemd.services.tunnel-xray = {
        description = "Клиент туннеля (VLESS + Reality, режим ${mode})";
        wantedBy = [ "multi-user.target" ];
        # sops-nix рендерит секреты и шаблоны в system.activationScripts.setupSecrets,
        # юнита sops-nix.service не существует — ordering к нему systemd молча
        # игнорировал. Активация идёт до старта юнитов, поэтому файл шаблона уже
        # на месте; перерисовку при смене значения обеспечивает restartUnits
        # у sops.templates.tunnel-xray ниже.
        after = [ "network-online.target" ] ++ lib.optional m2 "tunnel-routes.service";
        wants = [ "network-online.target" ] ++ lib.optional m2 "tunnel-routes.service";
        serviceConfig = {
          DynamicUser = true;
          LoadCredential = credentialId;
          ExecStartPre = "${startScript} test";
          ExecStart = "${startScript} run";
          # "+": адрес и маршрут ставит root, основной процесс остаётся с минимумом
          # прав (VPN-CLI-5).
          ExecStartPost = lib.optional m2 "+${routes.mkLinkUp { inherit (cfg) interface; }}";
          Restart = "on-failure";
          RestartSec = 2;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          # M1: без доп. привилегий (VPN-CLI-5). M2: CAP_NET_ADMIN для tun-in и
          # SO_MARK — DynamicUser без нужной группы, /dev/net/tun у хоста
          # crw-rw-rw-, но TUNSETIFF требует именно capability, не прав на файл
          # устройства (ARCH-6: включение — составом/значением опции, не отдельным
          # enable).
          CapabilityBoundingSet = lib.optionals m2 [ "CAP_NET_ADMIN" ];
          AmbientCapabilities = lib.optionals m2 [ "CAP_NET_ADMIN" ];
        };
      };
    };
}
