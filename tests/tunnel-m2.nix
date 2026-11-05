# Проверка свойства (STRUCTURE 5.1): режим M2 целиком — настоящие фичи клиента,
# настоящее рукопожатие Reality с выходом, захват пакетов на стороне провайдера.
# Покрывает то, что не выразить проверкой конфига: VPN-A5…A8 и M2-1, M2-2, M2-3,
# M2-5, M2-6, M2-8 гейта 7.3 (VPN_SUBSYSTEM 7.3). M2-4 (гибернация), M2-7 (нагрузка)
# и работа с настоящим Wi-Fi и корпоративным VPN проверяются на машине.
#
# Зачем именно так. Гейт 7.3 от 2026-10-14 проверялся на единственной рабочей сети и
# дал неверный вывод: сеть пропадала сразу по нескольким причинам, и различить их там
# было нельзя (ADR-41). Здесь сеть полностью внутренняя:
#
#   client ── isp ── relay (выход)
#      └───── isp ── web (сайты, DoH, резолвер локальной юрисдикции)
#
# Адреса «публичные», иначе правило geoip:private отправило бы всё напрямую, а маршрут
# по умолчанию у клиента настоящий, иначе конкретный маршрут main обошёл бы туннель.
#
# Секреты не расшифровываются: конфиг отрисован с фиктивными значениями той же
# техникой, что в tests/tunnel-config.nix, и подключён вместо шаблона sops.
#
# variant — для контрольных прогонов из docs/runbook/tunnel.md: возвращает по одному
# дефекты прежней конфигурации и меняет версии ядра. В `nix flake check` он пуст.
{
  pkgs,
  lib,
  inputs,
  nixosModules,
  variant ? { },
  ...
}:
let
  n = nixosModules // (variant.modules or { });

  fixtures = import ./fixtures/tunnel-m2.nix;

  clientIp = "10.0.0.2";
  clientBackupIp = "10.0.1.2";
  relayIp = fixtures.client."tunnel.endpoint";
  webIp = "93.184.216.34";
  ruWebIp = "77.88.55.60";
  dnsDirectIp = "77.88.8.8";

  tunnelOptions = mode: { inherit mode; } // (variant.tunnel or { });
  tunnelName = variant.tunnel.interface.name or "tunnel0";

  mkTestHost =
    mode:
    inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        n.host-facts
        n.nix-settings
        n.sops
        n.tunnel-facts
        n.tunnel-xray
        {
          my.host = {
            name = "tunnel-m2-fixture";
            class = "vm";
          };
          my.tunnel = tunnelOptions mode;
        }
      ];
    };

  xrayM2 = mkTestHost "m2";

  # Вместо sops-nix: он расшифровывал бы настоящие секреты репозитория, а ключей в ВМ
  # нет. Заглушка только принимает объявления фичи, сам конфиг приходит отрисованным.
  sopsStub =
    { lib, ... }:
    {
      options.sops = lib.mkOption { type = lib.types.attrsOf lib.types.anything; };
      config.sops.placeholder = lib.genAttrs (builtins.attrNames fixtures.client) (name: "<${name}>");
    };

  relayXray = (variant.relayXray or (_: xrayM2.pkgs.unstable.xray)) xrayM2.pkgs;

  clientConfig =
    mode:
    let
      host = mkTestHost mode;
      rendered = lib.foldl' (
        acc: name:
        lib.replaceStrings [ host.config.sops.placeholder.${name} ] [ fixtures.client.${name} ] acc
      ) host.config.sops.templates.tunnel-xray.content (builtins.attrNames fixtures.client);
      mutate = variant.mutateClientConfig or (c: c);
    in
    pkgs.writeText "tunnel-xray-${mode}.json" (builtins.toJSON (mutate (builtins.fromJSON rendered)));

  relayConfig = pkgs.writeText "relay.json" (
    builtins.toJSON {
      log.loglevel = "warning";
      inbounds = [
        {
          listen = "0.0.0.0";
          port = 443;
          protocol = "vless";
          settings = {
            decryption = "none";
            clients = [
              {
                id = fixtures.client."tunnel.clientId";
                flow = "xtls-rprx-vision";
              }
            ];
          };
          streamSettings = {
            network = "tcp";
            security = "reality";
            realitySettings = {
              target = "${webIp}:443";
              serverNames = [ fixtures.client."tunnel.serverName" ];
              privateKey = fixtures.realityPrivateKey;
              shortIds = [ fixtures.client."tunnel.shortId" ];
            };
          };
        }
      ];
      outbounds = [
        {
          tag = "direct";
          protocol = "freedom";
          settings = { };
          streamSettings.sockopt.domainStrategy = "UseIPv4";
        }
      ];
    }
  );

  # Сертификаты генерируются при сборке: цели маскировки Reality и DoH по IP, как у
  # настоящих резолверов в _tunnel-xray-policy.nix. Ключи тестовые и только в ВМ.
  certs = pkgs.runCommand "tunnel-m2-certs" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    mkdir $out
    cd $out
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
      -keyout ca.key -out ca.crt -days 36500 -subj /CN=tunnel-m2-ca
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
      -keyout server.key -out server.csr -subj /CN=target.test
    printf 'subjectAltName=DNS:target.test,IP:1.1.1.1,IP:9.9.9.9\n' > ext
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
      -out server.crt -days 36500 -extfile ext
  '';

  www = pkgs.runCommand "tunnel-m2-www" { } ''
    mkdir $out
    head -c 50M /dev/zero > $out/big
  '';

  probeImage = pkgs.dockerTools.buildImage {
    name = "probe";
    tag = "latest";
    copyToRoot = pkgs.buildEnv {
      name = "probe-root";
      paths = [ pkgs.busybox ];
    };
  };

  addresses = map (
    a:
    let
      parts = lib.splitString "/" a;
    in
    {
      address = builtins.elemAt parts 0;
      prefixLength = lib.toInt (builtins.elemAt parts 1);
    }
  );
in
pkgs.testers.runNixOSTest {
  name = "tunnel-m2${lib.optionalString (variant ? name) "-${variant.name}"}";

  # Клиенту нужен overlay из nix-settings (pkgs.unstable), как на настоящем хосте.
  node.pkgsReadOnly = false;

  nodes = {
    client =
      { lib, ... }:
      {
        imports = [
          n.host-facts
          n.nix-settings
          sopsStub
          n.firewall
          n.tunnel-facts
          n.tunnel-xray
          n.dns-resolver
          n.killswitch
          n.containers-docker
          (variant.client or { })
        ];

        my.host = {
          name = "tunnel-m2-fixture";
          class = "vm";
          stateVersion = "26.05";
          users = [ ];
        };
        my.tunnel = tunnelOptions "m2";

        virtualisation = {
          vlans = [
            1
            3
          ];
          memorySize = 2048;
        };
        # ARCH-13 (обоснование mkForce, здесь и у остальных узлов): частные адреса по
        # умолчанию задаёт сам фреймворк теста.
        networking = {
          interfaces.eth1.ipv4.addresses = lib.mkForce (addresses [ "${clientIp}/24" ]);
          interfaces.eth2.ipv4.addresses = lib.mkForce (addresses [ "${clientBackupIp}/24" ]);
          defaultGateway = {
            address = "10.0.0.1";
            interface = "eth1";
          };
        };

        # ARCH-13 (обоснование mkForce): шаблона sops здесь нет, конфиг клиента
        # подключается отрисованным.
        systemd.services.tunnel-xray.serviceConfig.LoadCredential =
          lib.mkForce "tunnel-xray.json:${clientConfig "m2"}";

        # Приложение, которое пытается выйти раньше клиента туннеля: на холодном старте
        # его трафик не должен дойти до провайдера (VPN-A8).
        systemd.services.early-probe = {
          after = [ "network.target" ];
          before = [ "tunnel-xray.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig.Type = "oneshot";
          script = "${lib.getExe pkgs.curl} -s --max-time 2 http://${webIp}/early || true";
        };

        # Откат одним параметром (VPN-MOD-5). Именно на нём сеть терялась 2026-10-14.
        specialisation.m1.configuration = {
          my.tunnel.mode = lib.mkForce "m1";
          systemd.services.tunnel-xray.serviceConfig.LoadCredential =
            lib.mkOverride 10 "tunnel-xray.json:${clientConfig "m1"}";
        };

        security.pki.certificateFiles = [ "${certs}/ca.crt" ];

        environment.systemPackages = [
          pkgs.conntrack-tools
          pkgs.curl
          pkgs.dnsutils
          pkgs.nftables
          pkgs.socat
        ];
      };

    isp =
      { lib, ... }:
      {
        virtualisation.vlans = [
          1
          2
          3
        ];
        networking = {
          firewall.enable = false;
          interfaces.eth1.ipv4.addresses = lib.mkForce (addresses [ "10.0.0.1/24" ]);
          interfaces.eth2.ipv4.addresses = lib.mkForce (addresses [
            "93.184.216.1/24"
            "45.77.0.1/24"
            "1.1.1.2/24"
            "9.9.9.2/24"
            "77.88.8.2/24"
            "77.88.55.1/24"
          ]);
          interfaces.eth3.ipv4.addresses = lib.mkForce (addresses [ "10.0.1.1/24" ]);
        };
        boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
        environment.systemPackages = [ pkgs.tcpdump ];
      };

    relay =
      { lib, ... }:
      {
        virtualisation.vlans = [ 2 ];
        networking = {
          firewall.enable = false;
          interfaces.eth1.ipv4.addresses = lib.mkForce (addresses [ "${relayIp}/24" ]);
          defaultGateway = {
            address = "45.77.0.1";
            interface = "eth1";
          };
        };
        systemd.services.relay-xray = {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            DynamicUser = true;
            AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
            ExecStart = "${relayXray}/bin/xray run -c ${relayConfig}";
          };
        };
      };

    web =
      { lib, ... }:
      {
        virtualisation.vlans = [ 2 ];
        networking = {
          firewall.enable = false;
          interfaces.eth1.ipv4.addresses = lib.mkForce (addresses [
            "${webIp}/24"
            "1.1.1.1/24"
            "9.9.9.9/24"
            "${dnsDirectIp}/24"
            "${ruWebIp}/24"
          ]);
          defaultGateway = {
            address = "93.184.216.1";
            interface = "eth1";
          };
        };

        # Страница отвечает адресом, с которого пришёл запрос: по нему видно путь.
        services.nginx = {
          enable = true;
          virtualHosts.site = {
            default = true;
            addSSL = true;
            http2 = true;
            listen = [
              {
                addr = webIp;
                port = 80;
              }
              {
                addr = ruWebIp;
                port = 80;
              }
              {
                addr = webIp;
                port = 443;
                ssl = true;
              }
            ];
            sslCertificate = "${certs}/server.crt";
            sslCertificateKey = "${certs}/server.key";
            root = www;
            locations."= /".extraConfig = ''
              default_type text/plain;
              return 200 "$remote_addr\n";
            '';
          };
        };

        # Резолвер локальной юрисдикции и DoH-резолверы на адресах из настоящей политики.
        services.coredns = {
          enable = true;
          config = ''
            .:53 {
              bind ${dnsDirectIp}
              hosts {
                ${ruWebIp} site.ru
                fallthrough
              }
            }

            https://.:443 {
              bind 1.1.1.1 9.9.9.9
              tls ${certs}/server.crt ${certs}/server.key
              hosts {
                ${webIp} foreign.test
                fallthrough
              }
            }

            tls://.:853 {
              bind 1.1.1.1
              tls ${certs}/server.crt ${certs}/server.key
              template IN TXT foreign.test {
                answer "foreign.test. 60 IN TXT tunnel-dot"
              }
            }
          '';
        };

        systemd.services.udp-echo = {
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig.ExecStart = "${lib.getExe pkgs.socat} UDP-LISTEN:7777,fork,reuseaddr,bind=${webIp} EXEC:${pkgs.coreutils}/bin/cat";
        };
      };
  };

  testScript = ''
    TUN = "${tunnelName}"
    CLIENT_IP = "${clientIp}"
    RELAY_IP = "${relayIp}"
    WEB = "http://${webIp}/"

    # Что клиент имеет право отправлять провайдеру: соединение с выходом и прямой
    # трафик политики. Всё остальное из захвата — утечка.
    LEAKS = (
        "ip and (src host ${clientIp} or src host ${clientBackupIp})"
        " and not (dst host ${relayIp} and tcp dst port 443)"
        " and not dst host ${dnsDirectIp} and not dst host ${ruWebIp}"
        " and not dst net 10.0.0.0/8 and not ip multicast and not ip broadcast"
    )


    def capture_start() -> None:
        isp.succeed("rm -f /tmp/capture.pcap")
        isp.succeed("systemd-run --unit=capture tcpdump -nn -U -i any -w /tmp/capture.pcap")
        # Заголовок файла появляется с первым пакетом, поэтому свой трафик на стороне выхода.
        isp.wait_until_succeeds("ping -c 1 -W 1 ${relayIp} && test -s /tmp/capture.pcap")


    def capture_leaks() -> str:
        isp.succeed("systemctl stop capture")
        return isp.succeed(f"tcpdump -nn -r /tmp/capture.pcap '{LEAKS}'").strip()


    def assert_no_leaks(what: str) -> None:
        leaks = capture_leaks()
        assert leaks == "", f"{what}: пакеты мимо туннеля:\n{leaks}"


    def fetch(url: str = WEB) -> str:
        return client.succeed(f"curl -sS --max-time 20 {url}").strip()


    def wait_tunnel() -> None:
        client.wait_until_succeeds(f"ip -4 route show table 7777 | grep -q 'default dev {TUN}'", timeout=60)
        client.wait_until_succeeds(f"curl -sS --max-time 10 {WEB} | grep -qx {RELAY_IP}", timeout=60)


    start_all()
    web.wait_for_unit("nginx.service")
    web.wait_for_unit("coredns.service")
    relay.wait_for_open_port(443)
    isp.wait_for_unit("multi-user.target")
    client.wait_for_unit("multi-user.target")
    client.wait_for_unit("tunnel-routes.service")
    client.wait_for_unit("tunnel-xray.service")

    ${variant.script or ''
      capture_start()
      wait_tunnel()

      with subtest("VPN-A5, M2-1: приложение без настройки прокси выходит с адреса выхода"):
          daemon = client.succeed(f"systemd-run --wait --pipe --quiet curl -sS --max-time 20 {WEB}").strip()
          assert daemon == RELAY_IP, f"ожидался адрес выхода, получено {daemon!r}"

      with subtest("M2-1, M2-5: зарубежное имя разрешается через DoH внутри туннеля"):
          assert fetch("http://foreign.test/") == RELAY_IP

      with subtest("M2-5: запрос к публичному резолверу мимо системного перехватывается"):
          answer = client.succeed("dig +short +time=5 +tries=1 @8.8.8.8 foreign.test").strip()
          assert answer == "${webIp}", f"перехвата нет: {answer!r}"

      ${lib.optionalString (!(variant.legacyCore or false)) ''
        with subtest("VPN-DNS-9: типы записей кроме A и AAAA получают настоящий ответ"):
            answer = client.succeed("dig +short +time=10 +tries=1 TXT foreign.test").strip()
            assert "tunnel-dot" in answer, f"пустой ответ вместо записи: {answer!r}"
      ''}

      with subtest("VPN-A6: локальная юрисдикция идёт напрямую, по имени и по адресу"):
          assert fetch("http://site.ru/") == CLIENT_IP
          assert fetch("http://${ruWebIp}/") == CLIENT_IP

      ${lib.optionalString (!(variant.legacyCore or false)) ''
        with subtest("M2-1: UDP"):
            echo = client.succeed("echo ping | timeout 10 socat -t5 - UDP:${webIp}:7777").strip()
            assert echo == "ping", f"UDP через туннель: {echo!r}"
      ''}

      with subtest("M2-8: контейнеры выходят через туннель и видят друг друга"):
          client.succeed("docker load < ${probeImage}")
          out = client.succeed(f"docker run --rm probe wget -qO- {WEB}").strip()
          assert out == RELAY_IP, f"контейнер вышел мимо туннеля: {out!r}"
          client.succeed("docker network create probes")
          client.succeed("docker run -d --name server --network probes probe sh -c 'echo hi > /index.html; httpd -f -p 80 -h /'")
          client.wait_until_succeeds("docker run --rm --network probes probe wget -qO- http://server/ | grep -qx hi", timeout=30)
          assert "${webIp}" in client.succeed("docker run --rm probe nslookup foreign.test")

      assert_no_leaks("обычная работа")

      with subtest("M2-6: минимальные права клиента (VPN-CLI-5)"):
          props = client.succeed("systemctl show tunnel-xray -p DynamicUser,AmbientCapabilities,CapabilityBoundingSet,NoNewPrivileges")
          assert "DynamicUser=yes" in props, props
          assert "AmbientCapabilities=cap_net_admin\n" in props, props
          assert "CapabilityBoundingSet=cap_net_admin\n" in props, props
          assert "NoNewPrivileges=yes" in props, props

      with subtest("VPN-CLI-8: адресаты соединений не попадают в журнал"):
          logged = client.succeed("journalctl -u tunnel-xray --no-pager -o cat")
          assert "accepted" not in logged and "${webIp}" not in logged, logged

      with subtest("rpfilter файрвола остаётся строгим"):
          assert "iif" in client.succeed("nft list chain inet nixos-fw rpfilter")

      with subtest("VPN-A8, VPN-KS-3: остановка клиента — отказ за 2 с и ни пакета мимо туннеля"):
          client.succeed(f"systemd-run --unit=download curl -s -o /dev/null --limit-rate 200k {WEB}big")
          client.wait_until_succeeds("systemctl is-active download")
          capture_start()
          client.succeed("systemctl stop tunnel-xray")
          routes = client.succeed("ip -4 route show table 7777")
          assert TUN not in routes and "unreachable" in routes, routes
          rc, took = client.succeed(
              "rc=0; start=$(date +%s%N); curl -s -o /dev/null --max-time 10 " + WEB + " || rc=$?; "
              + "echo $rc $(( ($(date +%s%N) - start) / 1000000 ))"
          ).split()
          assert rc == "7", f"ожидался отказ соединения (curl 7), получено {rc}"
          assert int(took) <= 2000, f"отказ занял {took} мс"
          rc, _ = client.execute("timeout 5 getent hosts foreign.test")
          assert rc != 0, "имя разрешилось без туннеля"
          client.execute("sleep 3")
          assert_no_leaks("клиент остановлен")
          client.execute("systemctl stop download")

      with subtest("Падение клиента: маршрут исчезает с устройством, клиент восстанавливается"):
          client.succeed("systemctl start tunnel-xray")
          wait_tunnel()
          routes = client.succeed("systemctl kill -s KILL tunnel-xray; sleep 0.5; ip -4 route show table 7777")
          assert TUN not in routes, routes
          wait_tunnel()

      with subtest("M2-3: смена сети без перезапуска клиента"):
          pid = client.succeed("systemctl show -p MainPID --value tunnel-xray").strip()
          client.succeed("ip route replace default via 10.0.1.1 dev eth2")
          client.succeed("ip link set eth1 down")
          wait_tunnel()
          assert fetch("http://${ruWebIp}/") == "${clientBackupIp}"
          client.succeed("ip link set eth1 up")
          client.succeed("ip route replace default via 10.0.0.1 dev eth1")
          wait_tunnel()
          assert pid == client.succeed("systemctl show -p MainPID --value tunnel-xray").strip()

      with subtest("M2-2: без маршрута по умолчанию нет петли"):
          client.succeed("ip route del default")
          before = int(client.succeed("conntrack -C"))
          for _ in range(5):
              client.execute(f"curl -s -o /dev/null --max-time 3 {WEB}")
          after = int(client.succeed("conntrack -C"))
          assert after - before < 50, f"соединения размножаются: {before} -> {after}"
          client.succeed("ip route replace default via 10.0.0.1 dev eth1")
          wait_tunnel()

      with subtest("VPN-A8: холодный старт без утечки"):
          capture_start()
          client.shutdown()
          client.start()
          client.wait_for_unit("multi-user.target")
          client.succeed("systemctl is-enabled early-probe")
          wait_tunnel()
          assert_no_leaks("холодный старт")

      with subtest("VPN-KS-6: портал авторизации снимает таблицу и правила и возвращает их"):
          # Те же команды, что в docs/runbook/tunnel.md.
          client.succeed(
              "systemd-run --unit=tunnel-portal-return --service-type=oneshot --on-active=10min /bin/sh -c "
              + "'systemctl start tunnel-routes.service && systemctl reload nftables.service'"
          )
          client.succeed("systemctl stop tunnel-routes.service")
          client.succeed("nft delete table inet killswitch")
          assert fetch() == CLIENT_IP
          client.succeed("systemctl start tunnel-portal-return.service")
          client.succeed("nft list table inet killswitch")
          wait_tunnel()

      with subtest("VPN-MOD-5: откат на M1 возвращает сеть и обратно"):
          client.succeed("/run/booted-system/specialisation/m1/bin/switch-to-configuration test")
          rules = client.succeed("ip -4 rule show")
          assert "7777" not in rules and "suppress" not in rules, rules
          assert "killswitch" not in client.succeed("nft list tables")
          assert fetch() == CLIENT_IP
          client.wait_until_succeeds(f"curl -sS --max-time 10 -x http://127.0.0.1:10809 {WEB} | grep -qx {RELAY_IP}", timeout=30)
          assert client.succeed("curl -sS --max-time 10 -x http://127.0.0.1:10809 http://site.ru/").strip() == CLIENT_IP
          client.succeed("/run/booted-system/bin/switch-to-configuration test")
          wait_tunnel()
    ''
    }
  '';
}
