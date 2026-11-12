# Проверка свойства (STRUCTURE 5.1): AI-A18 v3 — сетевые режимы агентов (AI-SBX-5, AI-SBX-6,
# AI-SEC-6, ADR-47, D21, D22). Не выразить как проверку конфига: нужны настоящий
# непривилегированный пользователь, pasta, правила nftables внутри пространства агента и
# «корпоративный VPN» с собственным DNS.
#
# Проверяется РЕАЛЬНЫЙ лаунчер (`modules/ai/_agents-tools-launcher.nix`), песочница, сеть и
# правила (`_agents-tools-{sandbox,net,nft}.nix`) — те же файлы, что собирает agents-tools.nix
# (AI-SBX-11). Подставлены только пакеты ролей: заглушки, которые выполняют команду из
# `--probe` (или, как веб-интерфейс dsh, слушают порт из `--port`).
#
# Стенд (одна ВМ): `tun0` — «линк корпоративного VPN» (veth в netns `vpnhost`: сервер
# 10.150.0.19, DNS-сервер 10.150.0.254 с зоной corp.test, зона привязана к tun0 в resolved,
# как dns.scopedZones на машине); `wan0` — «интернет» (netns `inet`, адрес 203.0.113.5,
# маршрут по умолчанию хоста). На loopback хоста — «шлюз», «база данных», служба из
# my.net.sensitiveLoopbackPorts (D21), а на адресах хоста — служба без привязки к loopback.
#
# У каждой негативной проверки есть контроль «тот же пользователь достаёт снаружи» (урок D17):
# без него «недоступно изнутри» ничего не доказывает.
{ pkgs, ... }:
let
  gitTool = pkgs.callPackage ../modules/ai/_agents-tools-git.nix { };
  nftTool = pkgs.callPackage ../modules/ai/_agents-tools-nft.nix { };
  netTool = pkgs.callPackage ../modules/ai/_agents-tools-net.nix {
    inherit nftTool;
    vpnLinks = [ "tun0" ];
    sensitivePorts = [ 9091 ];
  };
  sandboxExec = pkgs.callPackage ../modules/ai/_agents-tools-sandbox.nix { inherit gitTool; };
  dshPolicy = pkgs.callPackage ../modules/ai/_agents-tools-dsh-policy.nix { };

  # Заглушка агента: `--probe <команда...>` — выполнить команду внутри песочницы;
  # `--port N` — подняться как веб-интерфейс на этом порту и ждать.
  stub =
    name:
    pkgs.writeShellScriptBin name ''
      touch "$PWD/stub-started-${name}"
      printf '%s\n' "$@" > "$PWD/stub-args-${name}"
      port=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --probe) shift; exec "$@" ;;
          --port) port=$2; shift ;;
        esac
        shift
      done
      if [ -n "$port" ]; then
        ${pkgs.socat}/bin/socat "TCP-LISTEN:$port,bind=127.0.0.1,reuseaddr,fork" \
          SYSTEM:'echo HTTP/1.0 200 OK; echo; echo dsh-ui-ok' &
        exec sleep 300
      fi
    '';

  launcher = pkgs.callPackage ../modules/ai/_agents-tools-launcher.nix {
    inherit
      sandboxExec
      netTool
      gitTool
      dshPolicy
      ;
    dshWebPortBase = 11600;
    claudeCode = stub "claude";
    deepseekHarness = stub "dsh";
    aiderChat = stub "aider";
    aiderRole = "local-fast";
  };
in
pkgs.testers.runNixOSTest {
  name = "agent-network";

  nodes.machine = {
    users.groups.agent = { };
    users.users.agent = {
      isNormalUser = true;
      uid = 2000;
      group = "agent";
    };
    services.resolved.enable = true;

    environment.systemPackages = [
      launcher
      sandboxExec
      netTool
      nftTool
      gitTool
      pkgs.socat
      pkgs.curl
      pkgs.python3
      pkgs.bubblewrap
      pkgs.git
      pkgs.direnv
      pkgs.dnsmasq
      pkgs.iproute2
      pkgs.nftables
    ];
  };

  testScript = ''
    import shlex

    machine.wait_for_unit("multi-user.target")
    machine.succeed("loginctl enable-linger agent")
    machine.wait_for_unit("user@2000.service")

    HOME = "/home/agent"
    DSH_PORT = 11600 + 2000 - 1000


    def outside(cmd):
        return "su - agent -c " + shlex.quote(cmd)


    def as_agent(cmd):
        machine.succeed(outside(cmd))


    # --- Стенд: «корпоративный VPN» и «интернет» в отдельных netns, связанных veth с хостом.
    machine.succeed("""
      set -e
      ip netns add vpnhost
      ip link add tun0 type veth peer name vp0 netns vpnhost
      ip addr add 10.150.0.1/24 dev tun0
      ip link set tun0 up
      ip -n vpnhost addr add 10.150.0.19/24 dev vp0
      ip -n vpnhost addr add 10.150.0.254/24 dev vp0
      ip -n vpnhost link set vp0 up
      ip -n vpnhost link set lo up
      ip netns add inet
      ip link add wan0 type veth peer name wp0 netns inet
      ip addr add 198.51.100.1/24 dev wan0
      ip link set wan0 up
      ip -n inet addr add 198.51.100.10/24 dev wp0
      ip -n inet addr add 203.0.113.5/32 dev lo
      ip -n inet link set wp0 up
      ip -n inet link set lo up
      ip route add default via 198.51.100.10 dev wan0
    """)
    for unit, ns, cmd in [
        ("fix-vpn-web", "vpnhost", "${pkgs.python3}/bin/python3 -m http.server 8443 --bind 10.150.0.19"),
        (
            "fix-vpn-dns",
            "vpnhost",
            "${pkgs.dnsmasq}/bin/dnsmasq --no-daemon --no-resolv --no-hosts --bind-interfaces "
            "--listen-address=10.150.0.254 --address=/db.corp.test/10.150.0.19",
        ),
        ("fix-inet-web", "inet", "${pkgs.python3}/bin/python3 -m http.server 8081 --bind 203.0.113.5"),
    ]:
        machine.succeed(f"systemd-run --unit={unit} ip netns exec {ns} {cmd}")
    # Зона корпоративного DNS привязана к линку, как dns.scopedZones на машине.
    machine.succeed("resolvectl dns tun0 10.150.0.254 && resolvectl domain tun0 '~corp.test'")
    machine.wait_until_succeeds("curl -s --max-time 3 http://10.150.0.19:8443/ >/dev/null")
    machine.wait_until_succeeds("curl -s --max-time 3 http://203.0.113.5:8081/ >/dev/null")
    machine.wait_until_succeeds("curl -s --max-time 3 http://db.corp.test:8443/ >/dev/null")

    # --- Службы хоста: loopback (шлюз, база данных, D21) и адреса хоста.
    for name, addr, port, body in [
        ("gateway", "127.0.0.1", 11501, "gateway-ok"),
        ("database", "127.0.0.1", 5432, "database-ok"),
        ("sensitive", "127.0.0.1", 9091, "sensitive-ok"),
        ("hostsvc", "0.0.0.0", 18090, "hostsvc-ok"),
    ]:
        machine.succeed(f"install -d -o agent -g agent /srv/{name} && echo {body} > /srv/{name}/index.html")
        machine.succeed(
            f"systemd-run --uid=agent --unit=fix-{name} --working-directory=/srv/{name} "
            f"${pkgs.python3}/bin/python3 -m http.server {port} --bind {addr}"
        )
        machine.wait_until_succeeds(f"curl -s --max-time 3 http://127.0.0.1:{port}/ | grep -q {body}")
    machine.succeed(
        "systemd-run --uid=agent --unit=fix-abstract "
        "socat ABSTRACT-LISTEN:agents-abstract-fixture,fork SYSTEM:'echo alive'"
    )

    # Машинный слой, ключи шлюза по паре «агент × режим», корни проектов (AI-SEC-6).
    as_agent(f"mkdir -p {HOME}/.config/machine.d {HOME}/.config/ai {HOME}/work/p1 {HOME}/other/free {HOME}/other/marked/.ai")
    as_agent(
        f"printf '%s\n' 'export AI_GATEWAY_URL=http://127.0.0.1:11501' "
        f"'export AI_GATEWAY_KEYS_DIR=/run/llm-gateway/agent' > {HOME}/.config/machine.d/ai-gateway-env"
    )
    machine.succeed("install -d -m755 /run/llm-gateway /run/llm-gateway/agent")
    for key in ["aider-online", "aider-offline", "dsh-online", "dsh-offline"]:
        machine.succeed(f"echo {key}-key > /run/llm-gateway/agent/{key} && chown agent:agent /run/llm-gateway/agent/{key}")
    ROOTS = f"{HOME}/.config/ai/roots.toml"
    as_agent(f"printf '%s\n' '[[root]]' 'path = \"~/work\"' 'cloud = \"deny\"' > {ROOTS}")
    as_agent(f"touch {HOME}/other/marked/.ai/offline")

    # Пробы: одни и те же снаружи (контроль) и внутри песочницы. Только `k=v`.
    PROBE = r"""
    get() { curl -s --max-time 3 "$2" 2>/dev/null | head -c 40 | tr -d '\n'; echo; }
    for t in gateway:http://127.0.0.1:11501/ db:http://127.0.0.1:5432/ sens:http://127.0.0.1:9091/ \
             vpnip:http://10.150.0.19:8443/ vpnname:http://db.corp.test:8443/ inet:http://203.0.113.5:8081/ \
             hosttun:http://10.150.0.1:18090/ hostwan:http://198.51.100.1:18090/; do
      n=''${t%%:*}; echo "$n=$(get x "''${t#*:}")"
    done
    if socat -T3 -u /dev/null ABSTRACT-CONNECT:agents-abstract-fixture 2>/dev/null; then echo abstract=OPEN; else echo abstract=CLOSED; fi
    echo "nics=$(tail -n +3 /proc/net/dev | cut -d: -f1 | tr -d ' ' | sort | tr '\n' ',')"
    if test -S /nix/var/nix/daemon-socket/socket; then echo nixd=OPEN; else echo nixd=CLOSED; fi
    if nft add table inet probe 2>/dev/null; then echo nftw=OPEN; else echo nftw=CLOSED; fi
    echo "resolv=$(grep -m1 nameserver /etc/resolv.conf)"
    echo "proxyenv=$(printenv http_proxy)"
    echo "key=$(printenv OPENAI_API_KEY)"
    echo "dskey=$(printenv DEEPSEEK_API_KEY)"
    echo "dsurl=$(printenv DEEPSEEK_BASE_URL)"
    """


    def parse(out):
        res = {}
        for line in out.splitlines():
            if "=" in line and line.split("=", 1)[0].isidentifier():
                k, v = line.split("=", 1)
                res[k] = v
        return res


    def launch(args, project):
        """Реальный agent-launcher с заглушкой роли; stderr вместе со stdout."""
        return machine.execute(outside(f"cd {project} && agent-launcher {args} 2>&1"))


    def probe_in(role_args, project):
        status, out = launch(f"{role_args} -- --probe sh -c {shlex.quote(PROBE)}", project)
        assert status == 0, f"запуск не удался: {out}"
        return out, parse(out)


    def assert_clean():
        """После выхода не остаётся ни pasta, ни охранника, ни файлов resolv.conf."""
        machine.wait_until_fails("pgrep -u agent -x pasta", timeout=30)
        machine.fail("pgrep -u agent -f 'agents-net guard'")
        machine.fail("ls /run/user/2000 | grep -q agents-resolv")


    # === Контроль: снаружи ВСЁ достижимо тем же пользователем ================
    ctl = parse(machine.succeed(outside(f"sh -c {shlex.quote(PROBE.replace('nft add table inet probe', 'true'))}")))
    expect = {
        "gateway": "gateway-ok", "db": "database-ok", "sens": "sensitive-ok",
        "hosttun": "hostsvc-ok", "hostwan": "hostsvc-ok",
    }
    for k, body in expect.items():
        assert ctl[k] == body, f"контроль: {k} должен быть достижим снаружи: {ctl}"
    # Страницы http.server «VPN» и «интернета» — листинг каталога; контроль — непустой ответ.
    for k in ["vpnip", "vpnname", "inet"]:
        assert ctl[k] != "", f"контроль: {k} должен быть достижим снаружи: {ctl}"
    assert ctl["abstract"] == "OPEN", ctl

    # === online (по умолчанию): сеть как у пользователя ========================
    out, r = probe_in("aider", f"{HOME}/other/free")
    assert "режим online" in out, f"AI-SEC-6: по умолчанию online: {out}"
    assert r["key"] == "aider-online-key", "ключ шлюза — по режиму online"
    assert r["gateway"] == "gateway-ok", f"AI-A18: шлюз: {out}"
    assert r["db"] == "database-ok", f"AI-A18: loopback хоста (база данных на localhost): {out}"
    assert r["vpnip"] != "", f"AI-A18/D22: VPN-хост по адресу: {out}"
    assert r["vpnname"] != "", f"AI-A18/D22: VPN-хост по имени (DNS-зона через резолвер хоста): {out}"
    assert r["inet"] != "", f"AI-A18: интернет по маршрутам хоста: {out}"
    assert r["hosttun"] == "hostsvc-ok", f"AI-A18: адреса хоста в online доступны (Р13): {out}"
    assert r["sens"] == "", f"D21: порт службы без аутентификации закрыт правилами в online: {out}"
    assert r["abstract"] == "CLOSED", f"AI-A18: абстрактный сокет хоста недоступен: {out}"
    assert r["nftw"] == "CLOSED", f"AI-A18: правила неизменяемы изнутри: {out}"
    # Внутри — loopback и tap pasta (носит имя внешнего интерфейса хоста); интерфейсов хоста нет.
    assert set(r["nics"].split(",")) - {""} == {"lo", "wan0"}, f"отдельное пространство сети: {r['nics']}"
    assert r["nixd"] == "OPEN", "в online сокет демона сборки виден"
    assert r["resolv"] == "nameserver 169.254.1.1", f"свой resolv.conf песочницы: {r['resolv']}"
    assert r["proxyenv"] == "", "в M2 переменных прокси нет"
    assert_clean()

    # === offline: шлюз, DNS и сети VPN; остальное, включая адреса хоста, закрыто ======
    out, r = probe_in("aider --offline", f"{HOME}/other/free")
    assert "режим offline" in out, out
    assert r["key"] == "aider-offline-key", "ключ шлюза — по режиму offline"
    assert r["gateway"] == "gateway-ok", f"AI-A18: шлюз в offline доступен: {out}"
    assert r["vpnip"] != "" and r["vpnname"] != "", f"AI-A18: сети VPN и их DNS в offline доступны: {out}"
    for k in ["db", "sens", "inet", "hosttun", "hostwan"]:
        assert r[k] == "", f"AI-A18: {k} в offline закрыт (в том числе адрес хоста на линке VPN): {out}"
    assert r["abstract"] == "CLOSED" and r["nftw"] == "CLOSED", out
    assert r["nixd"] == "CLOSED", "AI-SBX-5: сокет демона сборки в offline скрыт"
    assert_clean()

    # === Корни проекта (roots.toml): cloud = "deny" → offline; маркер проекта не действует ===
    out, r = probe_in("aider", f"{HOME}/work/p1")
    assert "режим offline" in out and r["inet"] == "" and r["gateway"] == "gateway-ok", f"корень deny → offline: {out}"
    out, r = probe_in("aider", f"{HOME}/other/marked")
    assert "режим online" in out and r["inet"] != "", f"AI-SEC-5: маркер .ai/offline в проекте ничего не меняет: {out}"
    status, out = launch("aider --online", f"{HOME}/other/free")
    assert status != 0 and "--online больше нет" in out, out
    # Файл есть, но не разобран — отказ запуска, а не молчаливый online.
    as_agent(f"cp {ROOTS} {ROOTS}.ok && printf '%s\n' '[[root' > {ROOTS}")
    machine.succeed(f"rm -f {HOME}/other/free/stub-started-aider")
    status, out = launch("aider", f"{HOME}/other/free")
    assert status != 0 and "не разобран" in out, f"roots.toml сломан — отказ: {out}"
    machine.fail(f"test -e {HOME}/other/free/stub-started-aider")
    as_agent(f"printf '%s\n' '[[root]]' 'cloud = \"maybe\"' 'path = \"~/x\"' > {ROOTS}")
    status, out = launch("aider", f"{HOME}/other/free")
    assert status != 0 and "допустимо deny | allow" in out, out
    as_agent(f"mv {ROOTS}.ok {ROOTS}")
    # Файла нет совсем — облако разрешено по умолчанию.
    as_agent(f"mv {ROOTS} {ROOTS}.off")
    out, r = probe_in("aider", f"{HOME}/work/p1")
    assert "режим online" in out and r["inet"] != "", f"без roots.toml — online: {out}"
    as_agent(f"mv {ROOTS}.off {ROOTS}")

    # === claude: подписка — в offline не запускается =========================
    status, out = launch("claude", f"{HOME}/work/p1")
    assert status != 0 and "offline не запускается" in out, f"claude в offline: отказ: {out}"
    machine.fail(f"test -e {HOME}/work/p1/stub-started-claude")
    out, r = probe_in("claude", f"{HOME}/other/free")
    assert r["vpnname"] != "" and r["inet"] != "" and r["key"] == "", f"claude в online: сеть хоста, ключа шлюза нет: {out}"

    # === Fail-closed (AI-SBX-6): не поднялась сеть агента — агент не стартует ===========
    machine.succeed("sysctl -w user.max_user_namespaces=0")
    machine.succeed(f"rm -f {HOME}/other/free/stub-started-aider")
    status, out = launch("aider", f"{HOME}/other/free")
    machine.succeed("sysctl -w user.max_user_namespaces=15000")
    assert status != 0, f"AI-SBX-6: без пространств имён агент не запускается: {out}"
    machine.fail(f"test -e {HOME}/other/free/stub-started-aider")
    # Охранник сам по себе (без `agents-net run`) команду не запускает.
    machine.fail(outside("agents-net guard -- true"))

    # === dsh нативно (R9.18, AI-ROLE-5): окружение, политика патчем, профили не пишутся ==
    DSH_PROFILES = f"{HOME}/.local/state/agents/dsh/dsh-home/profiles"
    as_agent(f"mkdir -p {DSH_PROFILES}/web {DSH_PROFILES}/headless")
    # Прежний лаунчер писал свой патч с меткой — его убираем; файл интерфейса не трогаем.
    as_agent(f"printf '%s\n' '# Сгенерировано agent-launcher (R8.6, R9.14) — правки будут перезаписаны.' '- id: llm-deepseek' > {DSH_PROFILES}/web/cordis.patch.yml")
    as_agent(f"printf '%s\n' '- id: agent-default-model' '  config:' '    model: deepseek-v4-pro' > {DSH_PROFILES}/headless/cordis.patch.yml")
    out, r = probe_in("dsh", f"{HOME}/other/free")
    assert "режим online" in out, out
    assert r["dskey"] == "dsh-online-key", f"ключ dsh — значением в окружении, по режиму online: {out}"
    assert r["dsurl"] == "http://127.0.0.1:11501/anthropic", f"подключение окружением: {out}"
    args = machine.succeed(f"cat {HOME}/other/free/stub-args-dsh")
    assert "--patch\n${dshPolicy}\n" in args, f"политика Nix — флагом --patch из хранилища: {args}"
    assert "dsh-online-key" not in args, f"ключ не в argv: {args}"
    machine.fail(f"test -e {DSH_PROFILES}/web/cordis.patch.yml")  # метка лаунчера — файл убран
    assert "deepseek-v4-pro" in machine.succeed(f"cat {DSH_PROFILES}/headless/cordis.patch.yml"), "файл интерфейса сохранён"
    out, r = probe_in("dsh --offline", f"{HOME}/other/free")
    assert r["dskey"] == "dsh-offline-key", f"ключ dsh по режиму offline: {out}"
    status, out = launch("dsh -- 'сделай что-нибудь'", f"{HOME}/other/free")
    args = machine.succeed(f"cat {HOME}/other/free/stub-args-dsh")
    assert args.startswith("--profile\nheadless\n--patch\n${dshPolicy}\n"), args
    # Без ключа шлюза окружение подключения не задаётся (AI-GW-9).
    machine.succeed("mv /run/llm-gateway/agent/dsh-online /run/llm-gateway/agent/dsh-online.off")
    out, r = probe_in("dsh", f"{HOME}/other/free")
    assert r["dskey"] == "" and r["dsurl"] == "", f"без ключа окружение подключения пусто: {out}"
    machine.succeed("mv /run/llm-gateway/agent/dsh-online.off /run/llm-gateway/agent/dsh-online")

    # === dsh: веб-интерфейс внутри пространства сети открывается с хоста (публикация) ==
    as_agent(f"rm -f {HOME}/other/free/stub-started-dsh")
    machine.succeed(outside(f"cd {HOME}/other/free && (agent-launcher dsh > /tmp/dsh.log 2>&1 &)"))
    machine.wait_until_succeeds(f"curl -s --max-time 3 http://127.0.0.1:{DSH_PORT}/ | grep -q dsh-ui-ok", timeout=60)
    # Публикация — только на 127.0.0.1 хоста.
    machine.fail(f"curl -s --max-time 3 http://10.150.0.1:{DSH_PORT}/")
    machine.succeed("pkill -u agent -x sleep")
    machine.wait_until_fails("pgrep -u agent -f agent-launcher", timeout=60)
    assert_clean()
    machine.fail(f"curl -s --max-time 3 http://127.0.0.1:{DSH_PORT}/")

    # Порт хоста занят — публикация не поднялась, агент не стартует (AI-SBX-6).
    machine.succeed(
        f"systemd-run --uid=agent --unit=fix-busy "
        f"socat TCP-LISTEN:{DSH_PORT},bind=127.0.0.1,reuseaddr,fork SYSTEM:'echo busy'"
    )
    machine.wait_for_open_port(DSH_PORT)
    as_agent(f"rm -f {HOME}/other/free/stub-started-dsh")
    status, out = launch("dsh", f"{HOME}/other/free")
    assert status != 0, f"AI-SBX-6: порт занят — агент не стартует: {out}"
    machine.fail(f"test -e {HOME}/other/free/stub-started-dsh")
    machine.succeed("systemctl stop fix-busy")
    assert_clean()
  '';
}
