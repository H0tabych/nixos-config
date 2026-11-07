# Проверка свойства (STRUCTURE 5.1): AI-A18 — сетевые режимы агентов (AI-SBX-5,
# AI-SEC-6, ADR-44) не выразить как проверку конфига: нужен настоящий
# непривилегированный пользователь, bubblewrap с отдельным netns и слушатели на
# loopback хоста.
#
# Проверяется РЕАЛЬНЫЙ лаунчер (`modules/ai/_agents-tools-launcher.nix`), песочница
# и мосты (`_agents-tools-net.nix`) — те же файлы, что собирает agents-tools.nix
# (AI-SBX-11). Подставлены только пакеты ролей: заглушки, которые запускают
# команду из аргумента `--probe` (или, как веб-интерфейс dsh, слушают порт из
# `--port`). Модели, сеть наружу и туннель настоящими быть не обязаны: HTTP-вход
# туннеля здесь — заглушка-прокси на loopback, а правило «частные адреса через
# HTTP-вход не открываются» проверяет tests/tunnel-config.nix на настоящем xray.
#
# У каждой негативной проверки есть контроль «тот же пользователь достаёт до порта
# снаружи» (урок D17): без него «недоступно изнутри» ничего не доказывает.
{ pkgs, ... }:
let
  gitTool = pkgs.callPackage ../modules/ai/_agents-tools-git.nix { };
  netTool = pkgs.callPackage ../modules/ai/_agents-tools-net.nix { };
  sandboxExec = pkgs.callPackage ../modules/ai/_agents-tools-sandbox.nix { inherit gitTool netTool; };
  dshProfile = pkgs.callPackage ../modules/ai/_agents-tools-dsh-profile.nix {
    dshRole = "cost-autonomous";
  };

  # Заглушка агента: `--probe <команда...>` — выполнить команду внутри песочницы;
  # `--port N` — подняться как веб-интерфейс на этом порту и ждать.
  stub =
    name:
    pkgs.writeShellScriptBin name ''
      touch "$PWD/stub-started-${name}"
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
      dshProfile
      ;
    tunnelHttpPort = 10809;
    dshWebPortBase = 11600;
    claudeCode = stub "claude";
    deepseekHarness = stub "dsh";
    aiderChat = stub "aider";
    aiderRole = "local-fast";
  };

  # Заглушка HTTP-входа туннеля: прокси для обычных GET с абсолютным адресом.
  proxyPy = pkgs.writeText "proxy.py" ''
    import http.server, socketserver, urllib.request

    class H(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            with urllib.request.urlopen(self.path, timeout=5) as r:
                body = r.read()
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    class S(socketserver.ThreadingMixIn, http.server.HTTPServer):
        daemon_threads = True

    S(("127.0.0.1", 10809), H).serve_forever()
  '';
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
    services.openssh.enable = true;

    environment.systemPackages = [
      launcher
      sandboxExec
      netTool
      gitTool
      pkgs.socat
      pkgs.curl
      pkgs.python3
      pkgs.bubblewrap
      pkgs.git
      pkgs.direnv
    ];
  };

  testScript = ''
    import shlex

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("sshd.service")
    machine.succeed("loginctl enable-linger agent")
    machine.wait_for_unit("user@2000.service")

    HOME = "/home/agent"
    DSH_PORT = 11600 + 2000 - 1000


    def outside(cmd):
        return "su - agent -c " + shlex.quote(cmd)


    def as_agent(cmd):
        machine.succeed(outside(cmd))


    # --- Фикстуры на loopback хоста: «шлюз», «инференс», «внешний хост», прокси.
    # «Внешний хост» — на 127.0.0.2: адрес не входит в no_proxy песочницы
    # (localhost, 127.0.0.1), поэтому клиент идёт к нему через прокси.
    for name, addr, port, body in [
        ("gateway", "127.0.0.1", 11501, "gateway-ok"),
        ("inference", "127.0.0.1", 11434, "inference-ok"),
        ("external", "127.0.0.2", 18080, "external-ok"),
    ]:
        machine.succeed(f"install -d -o agent -g agent /srv/{name} && echo {body} > /srv/{name}/index.html")
        machine.succeed(
            f"systemd-run --uid=agent --unit=fix-{name} --working-directory=/srv/{name} "
            f"${pkgs.python3}/bin/python3 -m http.server {port} --bind {addr}"
        )
        machine.wait_until_succeeds(f"curl -s --max-time 3 http://{addr}:{port}/ | grep -q {body}")
    machine.succeed("systemd-run --uid=agent --unit=fix-proxy ${pkgs.python3}/bin/python3 ${proxyPy}")
    machine.wait_for_open_port(10809)
    machine.succeed(
        "systemd-run --uid=agent --unit=fix-abstract "
        "socat ABSTRACT-LISTEN:agents-abstract-fixture,fork SYSTEM:'echo alive'"
    )

    # Машинный слой, ключи шлюза по паре «агент × режим», корни рабочих деревьев.
    as_agent(f"mkdir -p {HOME}/.config/machine.d {HOME}/.config/ai {HOME}/work/p1 {HOME}/other/free {HOME}/other/marked/.ai")
    as_agent(
        f"printf '%s\n' 'export AI_GATEWAY_URL=http://127.0.0.1:11501' "
        f"'export AI_GATEWAY_KEYS_DIR=/run/llm-gateway/agent' > {HOME}/.config/machine.d/ai-gateway-env"
    )
    machine.succeed("install -d -m755 /run/llm-gateway /run/llm-gateway/agent")
    for key in ["aider-online", "aider-offline"]:
        machine.succeed(f"echo {key}-key > /run/llm-gateway/agent/{key} && chown agent:agent /run/llm-gateway/agent/{key}")
    as_agent(f"printf '%s\n' '# рабочие деревья' '~/work' > {HOME}/.config/ai/work-roots")
    as_agent(f"touch {HOME}/other/marked/.ai/offline")

    # Пробы: одни и те же снаружи (контроль) и внутри песочницы. Только `k=v`.
    PROBE = r"""
    echo "gateway=$(curl -s --max-time 3 http://127.0.0.1:11501/ 2>/dev/null)"
    echo "ext_direct=$(curl -s --max-time 3 --noproxy '*' http://127.0.0.2:18080/ 2>/dev/null)"
    echo "ext_proxy=$(curl -s --max-time 3 http://127.0.0.2:18080/ 2>/dev/null)"
    for t in inference:127.0.0.1:11434 ssh:127.0.0.1:22 resolver:127.0.0.53:53 proxyport:127.0.0.1:10809; do
      n=$(echo "$t" | cut -d: -f1); a=$(echo "$t" | cut -d: -f2-)
      if socat -T3 -u /dev/null "TCP:$a" 2>/dev/null; then echo "$n=OPEN"; else echo "$n=CLOSED"; fi
    done
    if socat -T3 -u /dev/null ABSTRACT-CONNECT:agents-abstract-fixture 2>/dev/null; then echo abstract=OPEN; else echo abstract=CLOSED; fi
    echo "nics=$(tail -n +3 /proc/net/dev | cut -d: -f1 | tr -d ' ' | tr '\n' ',')"
    if test -S /nix/var/nix/daemon-socket/socket; then echo nixd=OPEN; else echo nixd=CLOSED; fi
    echo "proxyenv=$(printenv http_proxy)"
    echo "key=$(printenv OPENAI_API_KEY)"
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
        cmd = f"cd {project} && agent-launcher {args} 2>&1"
        return machine.execute(outside(cmd))


    def probe_in(role_args, project):
        status, out = launch(f"{role_args} -- --probe sh -c {shlex.quote(PROBE)}", project)
        assert status == 0, f"запуск не удался: {out}"
        return out, parse(out)


    def assert_no_bridges():
        machine.fail("pgrep -u agent -f agents-bridge")
        machine.fail("ls /run/user/2000 | grep -q agents-bridge")


    # === Контроль: снаружи ВСЁ достижимо тем же пользователем ================
    out = machine.succeed(outside(f"sh -c {shlex.quote(PROBE)}"))
    ctl = parse(out)
    assert ctl["gateway"] == "gateway-ok", out
    assert ctl["ext_direct"] == "external-ok" and ctl["ext_proxy"] == "external-ok", out
    for k in ["inference", "ssh", "resolver", "proxyport", "abstract"]:
        assert ctl[k] == "OPEN", f"контроль: {k} должен быть достижим снаружи: {out}"

    # === offline (корень рабочих деревьев): только шлюз ======================
    out, r = probe_in("aider", f"{HOME}/work/p1")
    assert "режим offline" in out, f"AI-SEC-6: проект под корнем — offline по умолчанию: {out}"
    assert r["gateway"] == "gateway-ok", f"AI-A18: шлюз в offline доступен: {out}"
    assert r["key"] == "aider-offline-key", "ключ шлюза — по режиму offline"
    for k in ["inference", "ssh", "resolver", "proxyport", "abstract"]:
        assert r[k] == "CLOSED", f"AI-A18: {k} в offline недоступен: {out}"
    assert r["ext_direct"] == "" and r["ext_proxy"] == "", f"AI-A18: в offline нет выхода: {out}"
    assert r["proxyenv"] == "", "в offline переменных прокси нет"
    assert r["nics"] == "lo,", f"AI-SBX-5: в netns только lo: {r['nics']}"
    assert r["nixd"] == "CLOSED", "AI-SBX-5: сокет демона сборки в offline скрыт"
    assert_no_bridges()

    # Маркер проекта и флаг --offline.
    out, r = probe_in("aider", f"{HOME}/other/marked")
    assert "режим offline" in out and r["ext_proxy"] == "", f"маркер .ai/offline → offline: {out}"
    out, r = probe_in("aider --offline", f"{HOME}/other/free")
    assert "режим offline" in out and r["ext_proxy"] == "", f"--offline → offline: {out}"

    # === online (прочие проекты и --online): шлюз и выход через мост прокси ===
    out, r = probe_in("aider", f"{HOME}/other/free")
    assert "режим online" in out, f"прочие проекты — online: {out}"
    assert r["gateway"] == "gateway-ok", "в online шлюз доступен"
    assert r["key"] == "aider-online-key", "ключ шлюза — по режиму online"
    assert r["ext_proxy"] == "external-ok", f"AI-A18: в online выход идёт через прокси: {out}"
    assert r["ext_direct"] == "", f"AI-A18: мимо прокси выхода нет (свой netns): {out}"
    assert r["proxyenv"] == "http://127.0.0.1:10809", out
    for k in ["inference", "ssh", "resolver", "abstract"]:
        assert r[k] == "CLOSED", f"AI-A18: {k} хоста в online недоступен: {out}"
    assert r["nics"] == "lo,", r["nics"]
    assert r["nixd"] == "OPEN", "в online сокет демона сборки виден"
    assert_no_bridges()

    out, r = probe_in("aider --online", f"{HOME}/work/p1")
    assert "режим online" in out, f"--online включает облако на запуск под корнем: {out}"
    assert r["ext_proxy"] == "external-ok" and r["key"] == "aider-online-key", out
    _, out = launch("aider -- --probe true", f"{HOME}/work/p1")
    assert "режим offline" in out, f"--online действует на один запуск: {out}"

    # === claude: подписка — в offline не запускается ==========================
    status, out = launch("claude", f"{HOME}/work/p1")
    assert status != 0 and "offline не запускается" in out, f"claude в offline: отказ: {out}"
    machine.fail(f"test -e {HOME}/work/p1/stub-started-claude")
    out, r = probe_in("claude --online", f"{HOME}/work/p1")
    assert r["ext_proxy"] == "external-ok" and r["gateway"] == "", (
        f"claude в online: выход через прокси, шлюз ему не нужен: {out}"
    )

    # === dsh: веб-интерфейс внутри netns открывается с хоста (обратный мост) ==
    as_agent(f"rm -f {HOME}/other/free/stub-started-dsh")
    machine.succeed(
        outside(f"cd {HOME}/other/free && (agent-launcher dsh > /tmp/dsh.log 2>&1 &)")
    )
    machine.wait_until_succeeds(f"curl -s --max-time 3 http://127.0.0.1:{DSH_PORT}/ | grep -q dsh-ui-ok", timeout=60)
    machine.succeed("pkill -u agent -x sleep")
    machine.wait_until_fails("pgrep -u agent -f agent-launcher", timeout=60)
    assert_no_bridges()
    machine.fail(f"curl -s --max-time 3 http://127.0.0.1:{DSH_PORT}/")

    # Порт хоста занят — мост не поднялся, агент не стартует (AI-SBX-6).
    machine.succeed(
        f"systemd-run --uid=agent --unit=fix-busy "
        f"socat TCP-LISTEN:{DSH_PORT},bind=127.0.0.1,reuseaddr,fork SYSTEM:'echo busy'"
    )
    machine.wait_for_open_port(DSH_PORT)
    as_agent(f"rm -f {HOME}/other/free/stub-started-dsh")
    status, out = launch("dsh", f"{HOME}/other/free")
    assert status != 0 and "занят" in out, f"AI-SBX-6: мост не поднялся — агент не стартует: {out}"
    machine.fail(f"test -e {HOME}/other/free/stub-started-dsh")
    machine.succeed("systemctl stop fix-busy")
    assert_no_bridges()
  '';
}
