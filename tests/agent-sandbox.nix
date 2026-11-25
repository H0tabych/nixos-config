# Проверка свойства (STRUCTURE 5.1): AI-A7 (тесты песочницы агентов) и AI-A8
# (внедрение инструкций не ведёт к утечке секретов) не выразить как
# `nix flake check` по формату конфига — нужен настоящий непривилегированный
# пользователь и реальный bubblewrap (AI-SBX-1…11).
#
# Зачем именно так. `agents-sandbox-exec` — та же функция
# (`modules/ai/_agents-tools-sandbox.nix`), которую использует
# `agents-tools.nix` (AI-SBX-11: лаунчер владеет только Nix) — тест строит её
# тем же вызовом `callPackage`, чтобы проверять ровно тот код, который
# реально запускается, а не отдельную копию.
#
# AI-A7 на реалистичных фикстурах (ADR-44, D17): настоящие сокеты сессии
# (слушатели socat в /run/user/2000, живая logind-сессия), системная шина,
# секреты 0400 владельца в /run/secrets/rendered, ключ расшифровки, профиль
# браузера, копия конфига шлюза. У каждой негативной проверки есть контроль
# «тот же пользователь читает/подключается снаружи» — без него «недоступно
# изнутри» ничего не доказывает (так D17 и случился).
#
# AI-A8 здесь операционализирован без живой модели: "вредоносный" файл
# инструкций внутри проекта пытается прочитать секрет за пределами
# песочницы — граница держится независимо от того, что написано в самом
# файле (AI-SBX-9), поэтому проверка остаётся верной даже если агент решит
# выполнить любое его содержимое буквально.
{
  pkgs,
  ...
}:
let
  gitTool = pkgs.callPackage ../modules/ai/_agents-tools-git.nix { };
  sandboxExec = pkgs.callPackage ../modules/ai/_agents-tools-sandbox.nix {
    inherit gitTool;
    mounts = import ../modules/ai/_agents-tools-sandbox-mounts.nix;
  };
  dshPolicy = pkgs.callPackage ../modules/ai/_agents-tools-dsh-policy.nix { };
in
pkgs.testers.runNixOSTest {
  name = "agent-sandbox";

  nodes.machine = {
    users.groups.agent = { };
    users.users.agent = {
      isNormalUser = true;
      uid = 2000;
      group = "agent";
    };

    # Как на машине: /etc/resolv.conf — симлинк в /run/systemd/resolve (R9.15,
    # EAI_AGAIN внутри песочницы, когда /run — пустой tmpfs).
    services.resolved.enable = true;

    environment.etc."dsh-policy.yml".source = dshPolicy;

    environment.systemPackages = [
      sandboxExec
      pkgs.socat
      gitTool
      pkgs.coreutils
      pkgs.bubblewrap
      pkgs.git
      pkgs.direnv
      pkgs.jq
    ];
  };

  testScript = ''
    import shlex

    machine.wait_for_unit("multi-user.target")

    AGENT = "/home/agent"
    PROJECT = f"{AGENT}/project"
    STATE = f"{AGENT}/state"


    def sandbox(cmd, opts="", mode="online", project=PROJECT, state=STATE, env=""):
        """Команда su-обёртки: agents-sandbox-exec от имени agent."""
        inner = f"{env} agents-sandbox-exec {project} {state} {mode} {opts} -- {cmd}"
        return "su - agent -c " + shlex.quote(inner)


    def outside(cmd):
        return "su - agent -c " + shlex.quote(cmd)


    def fixture_file(path, content, mode="0400"):
        """Файл-фикстура, владелец — agent (под $HOME создаёт сам agent)."""
        d = path.rsplit("/", 1)[0]
        if path.startswith(AGENT):
            machine.succeed(outside(f"mkdir -p {d} && echo {content} > {path} && chmod {mode} {path}"))
        else:
            machine.succeed(
                f"mkdir -p {d} && echo {content} > {path} && chown agent:agent {path} && chmod {mode} {path}"
            )


    # --- Фикстуры (AI-A7): настоящие формы из аудита D17, а не пустые проверки.
    # logind-сессия пользователя живёт, пока включён linger, — иначе
    # /run/user/2000 исчезает вместе с первой su-сессией и уносит фикстуры.
    machine.succeed("loginctl enable-linger agent")
    machine.wait_for_unit("user@2000.service")

    fixture_file("/home/agent/.ssh/id_ed25519", "fake-ssh-key", "0600")
    machine.succeed(outside("chmod 700 /home/agent/.ssh"))
    fixture_file("/home/agent/nixos-config/flake.nix", "repo-marker", "0644")
    # Ключ расшифровки секретов хоста и профиль браузера.
    fixture_file("/home/agent/.config/sops/age/keys.txt", "age-key-marker")
    fixture_file("/home/agent/.mozilla/firefox/x.default/logins.json", "browser-marker")
    # Секреты sops: каталог 0751, файлы пользователя 0400 — как у sops-nix.
    machine.succeed("install -d -m751 /run/secrets && install -d -m751 /run/secrets/rendered")
    fixture_file("/run/secrets/outside-secret", "top-secret")
    # Шлюз v2 (ADR-45): ключ доступа — копия для пользователя (root:agent 0440,
    # читается самим agent, как на машине); конфиг с ключами провайдера — худший случай: в каталоге
    # службы, читаемый пользователем (0600, не в $HOME).
    fixture_file("/run/llm-gateway/agent/dsh-online", "gw-access-key-marker", "0440")
    fixture_file("/var/lib/llm-gateway-agent/config.json", "gw-config-marker", "0600")
    machine.succeed(outside("mkdir -p /home/agent/project /home/agent/state"))
    machine.succeed("echo docker-socket-marker > /run/docker.sock")

    # Сокеты настоящей сессии: слушатели socat. Контроль «снаружи работает»
    # обязателен — иначе «изнутри недоступно» ничего не доказывает.
    for sock in ["wayland-0", "fixture-bus", "ssh-agent"]:
        machine.succeed(
            f"systemd-run --uid=agent --unit=fix-{sock} "
            f"socat UNIX-LISTEN:/run/user/2000/{sock},fork SYSTEM:'echo alive'"
        )
        machine.wait_until_succeeds(f"test -S /run/user/2000/{sock}")
    SOCKETS = [
        "/run/user/2000/wayland-0",
        "/run/user/2000/fixture-bus",
        "/run/user/2000/ssh-agent",
        "/run/dbus/system_bus_socket",
    ]
    for sock in SOCKETS:
        machine.succeed(f"test -S {sock}")
        if not sock.endswith("system_bus_socket"):
            assert "alive" in machine.succeed(outside(f"socat - UNIX-CONNECT:{sock}")), (
                f"контроль: сокет {sock} должен отвечать снаружи"
            )
    if machine.execute("test -S /run/user/2000/bus")[0] == 0:
        SOCKETS.append("/run/user/2000/bus")

    # Конфиги ~/.config: белый список и «чужие» каталоги; ai — симлинк в
    # рабочую копию dotfiles, как на машине.
    fixture_file("/home/agent/.dotfiles/ai/generated/claude.mcp.json", "ai-marker", "0644")
    machine.succeed(outside("ln -s /home/agent/.dotfiles/ai /home/agent/.config/ai"))
    fixture_file("/home/agent/.config/machine.d/ai-gateway-env", "machine-marker", "0644")
    fixture_file("/home/agent/.config/git/config", "'[gitmarker]'", "0644")
    fixture_file("/home/agent/.config/direnv/direnvrc", "direnvrc-marker", "0644")
    fixture_file("/home/agent/.config/claude-code/settings.json", "config-marker", "0644")
    fixture_file("/home/agent/.config/evil/x", "evil-marker", "0644")
    fixture_file("/home/agent/.local/share/direnv/allow/test", "allow-marker", "0644")
    fixture_file("/home/agent/.local/share/other/data", "other-marker", "0644")

    # Окружение внешней сессии, которого внутри быть не должно (AI-SBX-3).
    DIRTY_ENV = (
        "GITHUB_TOKEN=gh-secret-marker "
        "SSH_AUTH_SOCK=/run/user/2000/ssh-agent "
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/2000/bus "
        "SOPS_AGE_KEY_FILE=/home/agent/.config/sops/age/keys.txt"
    )


    def assert_hidden(label, path, marker, opts=""):
        # Контроль: снаружи тот же файл читается тем же пользователем.
        assert marker in machine.succeed(outside(f"cat {path}")), f"контроль: {path} должен читаться снаружи"
        status, out = machine.execute(sandbox(f"cat {path}", opts))
        assert status != 0 and marker not in out, f"AI-A7: {label} не должен быть читаем из песочницы ({path})"


    def sandbox_out(cmd, opts="", **kw):
        return machine.succeed(sandbox(cmd, opts, **kw))


    # === Обычный режим (AI-SBX-1/2/3): корень из разрешённого =================
    for label, path, marker in [
        ("ssh-ключ", "/home/agent/.ssh/id_ed25519", "fake-ssh-key"),
        ("репозиторий nixos-config", "/home/agent/nixos-config/flake.nix", "repo-marker"),
        ("секрет sops root", "/run/secrets/outside-secret", "top-secret"),
        ("ключ доступа к шлюзу 0440", "/run/llm-gateway/agent/dsh-online", "gw-access-key-marker"),
        ("конфиг шлюза с ключами провайдера", "/var/lib/llm-gateway-agent/config.json", "gw-config-marker"),
        ("ключ расшифровки секретов", "/home/agent/.config/sops/age/keys.txt", "age-key-marker"),
        ("профиль браузера", "/home/agent/.mozilla/firefox/x.default/logins.json", "browser-marker"),
        ("~/.config вне белого списка", "/home/agent/.config/evil/x", "evil-marker"),
        ("~/.config/claude-code без --config", "/home/agent/.config/claude-code/settings.json", "config-marker"),
        ("соседний каталог ~/.local/share", "/home/agent/.local/share/other/data", "other-marker"),
        ("рабочая копия dotfiles", "/home/agent/.dotfiles/ai/generated/claude.mcp.json", "ai-marker"),
    ]:
        assert_hidden(label, path, marker)

    # Сокеты сессии, системная шина, сокет рантайма контейнеров: путей нет вообще.
    for sock in SOCKETS + ["/run/docker.sock"]:
        status, _ = machine.execute(sandbox(f"test -e {sock}"))
        assert status != 0, f"AI-SBX-1: {sock} не должен существовать внутри песочницы"
    status, out = machine.execute(sandbox("socat - UNIX-CONNECT:/run/user/2000/fixture-bus"))
    assert status != 0 and "alive" not in out, "AI-SBX-1: к сокету сессии нельзя подключиться изнутри"

    # Корень — ровно перечень разрешённого.
    root = set(sandbox_out("ls /").split())
    assert root <= {"bin", "dev", "etc", "home", "nix", "proc", "run", "tmp", "usr"}, f"AI-SBX-1: лишнее в корне: {root}"
    run = set(sandbox_out("ls /run").split())
    assert run <= {"current-system", "systemd", "user"}, f"AI-SBX-1: лишнее в /run: {run}"
    assert sandbox_out("ls -A /run/user/2000").strip() == "", "XDG_RUNTIME_DIR роли должен быть пустым"
    assert sandbox_out("ls /run/user").split() == ["2000"], "в /run/user только каталог самой роли"
    # Сокет демона сборки — единственное, что нужно из хоста для nix внутри.
    sandbox_out("test -S /nix/var/nix/daemon-socket/socket")
    # ...и nix внутри действительно идёт через него, а не в локальное хранилище
    # (регрессия: «opening lock file ... Read-only file system»).
    assert "Store URL: daemon" in sandbox_out("nix --extra-experimental-features nix-command store info 2>&1"), "nix в песочнице должен идти через демон"

    # DNS (регрессия R9.14: /run пустой — resolv.conf-симлинк висел в пустоту).
    assert "nameserver" in machine.succeed(outside("cat /etc/resolv.conf")), "контроль: resolv.conf снаружи"
    assert "nameserver" in sandbox_out("cat /etc/resolv.conf"), "DNS: /etc/resolv.conf должен читаться внутри"

    # Окружение (AI-SBX-3): посторонних секретов нет, свои XDG есть.
    env_out = sandbox_out("printenv", env=DIRTY_ENV)
    for bad in ["gh-secret-marker", "SSH_AUTH_SOCK", "DBUS_SESSION_BUS_ADDRESS", "SOPS_AGE_KEY_FILE", "keys.txt"]:
        assert bad not in env_out, f"AI-SBX-3: {bad} не должен попасть в окружение агента"
    for want in [
        f"XDG_CACHE_HOME={STATE}/cache",
        f"XDG_STATE_HOME={STATE}/state",
        f"XDG_DATA_HOME={STATE}/data",
        "XDG_RUNTIME_DIR=/run/user/2000",
        "HOME=/home/agent",
        "NIX_REMOTE=daemon",
    ]:
        assert want in env_out.split("\n"), f"AI-SBX-2: ожидалось {want}"

    # Ключ доступа — значением через --pass-env и только им.
    assert sandbox_out(
        "printenv AGENT_KEY", "--pass-env AGENT_KEY", env="AGENT_KEY=key-from-env"
    ).strip() == "key-from-env", "--pass-env должен доносить значение в окружение агента"
    assert "AGENT_KEY" not in sandbox_out("printenv", env="AGENT_KEY=key-from-env"), (
        "без --pass-env переменная внутрь не попадает"
    )
    # ...и значение не светится в argv снаружи (ps), в отличие от --env NAME=VALUE.
    machine.succeed(
        "echo 'export AGENT_KEY=argv-key-marker; exec agents-sandbox-exec "
        f"{PROJECT} {STATE} online --pass-env AGENT_KEY -- sleep 20' "
        "> /home/agent/argv-probe.sh && chown agent:agent /home/agent/argv-probe.sh"
    )
    machine.execute("(su - agent -c 'sh /home/agent/argv-probe.sh' >/dev/null 2>&1 &)")
    machine.wait_until_succeeds("pgrep -u agent sleep")
    assert "argv-key-marker" not in machine.succeed("ps -eo args"), "AI-SBX-3: ключ не должен быть в argv"

    # Белый список ~/.config: читается и только на чтение; каталог роли — по --config.
    for path, marker in [
        ("/home/agent/.config/machine.d/ai-gateway-env", "machine-marker"),
        ("/home/agent/.config/ai/generated/claude.mcp.json", "ai-marker"),
        ("/home/agent/.config/git/config", "gitmarker"),
        ("/home/agent/.config/direnv/direnvrc", "direnvrc-marker"),
    ]:
        assert marker in sandbox_out(f"cat {path}"), f"AI-SBX-2: {path} из белого списка должен читаться"
        status, _ = machine.execute(sandbox(f"touch {path}-w"))
        assert status != 0, f"AI-SBX-2: {path} из белого списка — только чтение"
    assert "config-marker" in sandbox_out(
        "cat /home/agent/.config/claude-code/settings.json", "--config claude-code"
    ), "--config открывает каталог роли"
    status, _ = machine.execute(sandbox("true", "--config ../.ssh"))
    assert status != 0, "--config принимает имя каталога, не путь"

    # XDG роли: запись идёт в state-dir, а не в настоящий ~/.cache; база
    # разрешений direnv видна по новому XDG_DATA_HOME.
    sandbox_out("sh -c 'echo c > $HOME/.cache-probe; echo y > $XDG_CACHE_HOME/y'")
    machine.fail("test -e /home/agent/.cache-probe")
    machine.succeed("test -e /home/agent/state/cache/y")
    assert "allow-marker" in sandbox_out("sh -c 'cat $XDG_DATA_HOME/direnv/allow/test'"), (
        "AI-SBX-4: база разрешений direnv должна быть видна по $XDG_DATA_HOME/direnv"
    )

    # Запись: только project-dir и state-dir.
    sandbox_out(f"touch {PROJECT}/ok")
    machine.succeed(f"test -e {PROJECT}/ok")
    status, _ = machine.execute(sandbox("touch /etc/should-not-exist"))
    assert status != 0, "AI-SBX-2: запись вне project-dir/state-dir должна быть запрещена"
    machine.fail("test -e /etc/should-not-exist")

    # AI-A8: «вредоносный» файл инструкций ничего не достаёт (AI-SBX-9).
    machine.succeed(
        "echo 'cat /home/agent/.ssh/id_ed25519 /home/agent/.config/sops/age/keys.txt "
        "/run/llm-gateway/agent/dsh-online' "
        f"> {PROJECT}/malicious.sh && chown agent:agent {PROJECT}/malicious.sh"
    )
    status, out = machine.execute(sandbox(f"sh {PROJECT}/malicious.sh"))
    assert status != 0 and not any(m in out for m in ["fake-ssh-key", "age-key-marker", "gw-access-key-marker"]), (
        "AI-A8: файл инструкций внутри проекта не должен доставать секреты"
    )

    # AI-SBX-6 (fail-closed): ошибка bwrap не исполняет целевую команду.
    status, _ = machine.execute(
        sandbox(f"touch {STATE}/should-not-be-created", project="/home/agent/no-such-project")
    )
    assert status != 0, "AI-SBX-6: несуществующий project-dir должен останавливать запуск до exec"
    machine.fail(f"test -e {STATE}/should-not-be-created")

    # AI-SBX-2: project-dir = $HOME / предок / корень запрещены.
    for label, pdir in [("домашний каталог", "/home/agent"), ("предок", "/home"), ("корень", "/")]:
        status, _ = machine.execute(sandbox(f"touch {STATE}/breach", project=pdir))
        assert status != 0, f"AI-SBX-2: project-dir = {label} ({pdir}) должен быть запрещён"
        machine.fail(f"test -e {STATE}/breach")

    # AI-SBX-5 (ADR-47): прокси-переменные M1 (NET-10) из окружения запуска проходят как есть,
    # SOCKS (`all_proxy`) не передаётся; без них внутри ничего нет (M2).
    out = sandbox_out(
        "sh -c 'echo p=$http_proxy n=$no_proxy a=$all_proxy'",
        env="http_proxy=http://127.0.0.1:1 no_proxy=localhost all_proxy=socks5://127.0.0.1:2",
    )
    assert out.strip() == "p=http://127.0.0.1:1 n=localhost a=", f"AI-SBX-5: {out!r}"
    out = sandbox_out("sh -c 'echo p=$http_proxy n=$no_proxy'")
    assert out.strip() == "p= n=", f"AI-SBX-5: без переменных M1 внутри их нет: {out!r}"

    # §2.5 класс D: --app-path отдаёт приложению ЕГО каталог на запись.
    fixture_file("/home/agent/.appstate/sessions", "app-marker", "0644")
    assert "app-marker" in sandbox_out("cat /home/agent/.appstate/sessions", "--app-path /home/agent/.appstate")
    sandbox_out("touch /home/agent/.appstate/written", "--app-path /home/agent/.appstate")
    machine.succeed("test -e /home/agent/.appstate/written")
    status, out = machine.execute(
        sandbox("cat /home/agent/.ssh/id_ed25519", "--app-path /home/agent/.appstate")
    )
    assert status != 0 and "fake-ssh-key" not in out, "--app-path не открывает ничего, кроме переданного пути"

    # === AI-SBX-14: --device — узлы устройств хоста только по явной опции ==========
    # Реальных /dev/kvm и /dev/dri в тестовой ВМ может не быть: подставляем метку.
    machine.succeed("mkdir -p /dev/dri && touch /dev/dri/sbx-marker")
    status, _ = machine.execute(sandbox("test -e /dev/dri/sbx-marker"))
    assert status != 0, "AI-SBX-14: без --device узлов хоста в /dev песочницы нет"
    sandbox_out("test -e /dev/dri/sbx-marker", "--device dri")
    status, _ = machine.execute(sandbox("test -e /dev/dri/sbx-marker", "--device kvm"))
    assert status != 0, "AI-SBX-14: --device kvm не открывает dri"
    sandbox_out("true", "--device kvm")  # узла kvm на хосте может не быть: молча пропускается
    status, _ = machine.execute(sandbox("true", "--device sda"))
    assert status != 0, "AI-SBX-14: устройство вне белого списка — отказ"

    # === AI-SBX-15: --wayland — только сокет Wayland-сессии, остальное в /run/user скрыто ====
    WL = "env WAYLAND_DISPLAY=wayland-0"
    status, _ = machine.execute(sandbox("test -S /run/user/2000/wayland-0", env=WL))
    assert status != 0, "AI-SBX-15: без --wayland сокета Wayland в песочнице нет"
    sandbox_out("test -S /run/user/2000/wayland-0", "--wayland", env=WL)
    assert "alive" in sandbox_out("socat - UNIX-CONNECT:/run/user/2000/wayland-0", "--wayland", env=WL), (
        "AI-SBX-15: сокет Wayland должен отвечать изнутри"
    )
    assert "wayland-0" in sandbox_out("printenv WAYLAND_DISPLAY", "--wayland", env=WL)
    for hidden in ["fixture-bus", "ssh-agent"]:
        status, _ = machine.execute(sandbox(f"test -e /run/user/2000/{hidden}", "--wayland", env=WL))
        assert status != 0, f"AI-SBX-15: --wayland не открывает /run/user/2000/{hidden}"
    # Сокета нет — опция молча ничего не делает, переменных Wayland нет.
    status, _ = machine.execute(
        sandbox("printenv WAYLAND_DISPLAY", "--wayland", env="env WAYLAND_DISPLAY=absent XDG_RUNTIME_DIR=/nonexistent")
    )
    assert status != 0, "AI-SBX-15: без сокета WAYLAND_DISPLAY не задаётся"

    # === AI-SBX-12: --home-rw (роль claude). Урезанный набор AI-A7 ============
    HRW = "--home-rw"
    assert "fake-ssh-key" in sandbox_out("cat /home/agent/.ssh/id_ed25519", HRW), (
        "--home-rw действительно открывает $HOME (принятый риск AI-SBX-12)"
    )
    sandbox_out("touch /home/agent/written-outside-project", HRW)
    machine.succeed("test -e /home/agent/written-outside-project")
    for label, path, marker in [
        ("секрет sops", "/run/secrets/outside-secret", "top-secret"),
        ("ключ доступа к шлюзу", "/run/llm-gateway/agent/dsh-online", "gw-access-key-marker"),
        ("конфиг шлюза с ключами провайдера", "/var/lib/llm-gateway-agent/config.json", "gw-config-marker"),
    ]:
        assert_hidden(f"{label} (--home-rw)", path, marker, HRW)
    for sock in SOCKETS + ["/run/docker.sock"]:
        status, _ = machine.execute(sandbox(f"test -e {sock}", HRW))
        assert status != 0, f"AI-SBX-1 в --home-rw: {sock} не должен существовать"
    status, _ = machine.execute(sandbox("touch /etc/should-not-exist-homerw", HRW))
    assert status != 0, "AI-SBX-12: --home-rw не должен давать запись вне $HOME"
    machine.fail("test -e /etc/should-not-exist-homerw")
    status, _ = machine.execute(sandbox("true", HRW, project="/"))
    assert status != 0, "project-dir = / запрещён в любом режиме"

    # === AI-SBX-13 (ADR-48): песочница без проекта — основа долгоживущей =================
    status, _ = machine.execute(sandbox("true", project="-"))
    assert status != 0, "без проекта и без --home-rw — отказ (пустая песочница бессмысленна)"
    sandbox_out("touch /home/agent/written-noproject", HRW, project="-")
    machine.succeed("test -e /home/agent/written-noproject")
    status, out = machine.execute(sandbox("cat /run/secrets/outside-secret", HRW, project="-"))
    assert status != 0 and "top-secret" not in out, "без проекта граница вне $HOME та же"
    for sock in SOCKETS:
        status, _ = machine.execute(sandbox(f"test -e {sock}", HRW, project="-"))
        assert status != 0, f"без проекта: {sock} не должен существовать"
    # --info-file: сведения bwrap для входа (pid процесса внутри и id пространств).
    sandbox_out("true", f"{HRW} --info-file /home/agent/sbx.json", project="-")
    machine.succeed("""jq -e '."child-pid" > 0 and ."pid-namespace" > 0 and ."mnt-namespace" > 0' /home/agent/sbx.json""")
    # --print-env: окружение AI-SBX-3 потоком (NUL), ничего не запускает; ключ — не из argv.
    envs = machine.succeed(outside(
        "SSH_AUTH_SOCK=/run/user/2000/ssh GW_KEY=gw-key-value "
        "agents-sandbox-exec - /home/agent/state online --pass-env GW_KEY --env A=b --print-env | tr '\\0' '\\n'"
    )).splitlines()
    for kv in ["GW_KEY=gw-key-value", "A=b", "HOME=/home/agent", "NIX_REMOTE=daemon", "XDG_RUNTIME_DIR=/run/user/2000"]:
        assert kv in envs, f"--print-env: нет {kv}: {envs}"
    assert not any(e.startswith("SSH_AUTH_SOCK=") for e in envs), f"--print-env: только перечень AI-SBX-3: {envs}"

    # === Политика Nix для dsh (R9.14, R9.18): поиск, телеметрия, менеджер плагинов ==
    text = machine.succeed("cat /etc/dsh-policy.yml")
    for plugin in [
        "plugin-manager",
        "tool-plugin-manager",
        "ui-plugin-manager",
        "entry-customization",  # зависит от pluginNavigation ui-plugin-manager (иначе UI не грузится)
    ]:
        assert f"- id: {plugin}\n  disabled: true" in text, f"dsh: {plugin} должен быть выключен"
    # Родной поиск и загрузка страниц DeepSeek работают (ADR-051): ключ — провайдера, не шлюза.
    for plugin in ["web-search-deepseek", "web-deepseek-api", "tool-web"]:
        assert f"- id: {plugin}" not in text, f"dsh: {plugin} не должен быть выключен"
    for plugin, cfg in [
        ("session-telemetry-otel", "mode: DISABLED"),
        ("session-log-deepseek", "enabled: false"),
        ("plugin-package-inventory-deepseek", "enabled: false"),
    ]:
        assert f"- id: {plugin}\n  config:\n    {cfg}" in text, f"dsh: {plugin} — {cfg}"
    # Подключение и модель в политике не задаются: только окружение и интерфейс (ADR-051).
    assert "baseURL" not in text and "agent-default-model" not in text and "@GATEWAY_URL@" not in text

    # === AI-SBX-7, AI-A12 (ADR-44, R9.15): работа на месте ====================
    REPO = f"{AGENT}/proj-git"


    def in_repo(cmd):
        return outside(f"cd {REPO} && {cmd}")


    def sandbox_repo(cmd, opts=""):
        return sandbox(f"sh -c {shlex.quote(cmd)}", opts, project=REPO)


    # Фикстура: репозиторий с hooks/, info/, .envrc, core.hooksPath внутри дерева,
    # подмодулем и игнорируемым файлом. Идентичность — в .git/config репозитория.
    machine.succeed(outside("git init -q -b main /home/agent/sub-src"))
    machine.succeed(outside(
        "cd /home/agent/sub-src && git config user.name t && git config user.email t@t "
        "&& echo s > s.txt && git add . && git commit -qm sub"
    ))
    machine.succeed(outside(f"git init -q -b main {REPO}"))
    machine.succeed(in_repo(
        "git config user.name t && git config user.email t@t "
        "&& git config core.hooksPath scripts/hooks "
        "&& mkdir -p .git/hooks .git/info scripts/hooks "
        "&& printf '#!/bin/sh\nexit 0\n' > scripts/hooks/pre-commit && chmod +x scripts/hooks/pre-commit "
        "&& echo 'use flake' > .envrc && printf 'ignored.log\n.direnv\n' > .gitignore "
        "&& echo ignored > ignored.log && echo hi > README.md "
        "&& git -c protocol.file.allow=always submodule add -q /home/agent/sub-src sub "
        "&& git add -A && git commit -qm init && git branch side"
    ))
    machine.succeed(in_repo("test -f sub/.git && test -d .git/modules/sub/hooks"))

    # Правка из песочницы видна снаружи сразу; коммит проходит (объекты, ссылки,
    # индекс — на запись), ветка остаётся прежней; хук из core.hooksPath работает.
    machine.succeed(sandbox_repo("echo edit >> README.md"))
    assert "edit" in machine.succeed(in_repo("cat README.md")), "AI-SBX-7: правка должна быть видна снаружи"
    machine.succeed(sandbox_repo("git add -A && git commit -qm agent-commit && git branch inner"))
    assert machine.succeed(in_repo("git log -1 --format=%s")).strip() == "agent-commit", (
        "AI-SBX-7: коммит агента должен быть виден снаружи"
    )
    assert machine.succeed(in_repo("git branch --show-current")).strip() == "main"
    machine.succeed(in_repo("git rev-parse inner"))

    # Метаданные git — только чтение. Контроль: тот же пользователь снаружи пишет.
    for label, cmd, control in [
        ("git config", "git config user.name evil", "test -w .git/config"),
        ("дописывание в .git/config", "echo x >> .git/config", "test -w .git/config"),
        ("запись в .git/hooks", "touch .git/hooks/evil", "test -w .git/hooks"),
        ("запись в .git/info", "touch .git/info/evil", "test -w .git/info"),
        ("запись в core.hooksPath внутри дерева", "touch scripts/hooks/evil", "test -w scripts/hooks"),
        ("подмена хука из core.hooksPath", "echo x >> scripts/hooks/pre-commit", "test -w scripts/hooks/pre-commit"),
        (".envrc", "echo x >> .envrc", "test -w .envrc"),
        ("указатель подмодуля .git", "echo x >> sub/.git", "test -w sub/.git"),
        ("hooks подмодуля", "touch .git/modules/sub/hooks/evil", "test -w .git/modules/sub/hooks"),
        ("config подмодуля", "echo x >> .git/modules/sub/config", "test -w .git/modules/sub/config"),
        ("rm -rf .git/hooks", "rm -rf .git/hooks", "test -w .git/hooks"),
        ("mv .git/hooks", "mv .git/hooks .git/hooks.x", "test -w .git/hooks"),
        ("mv .git (привязан к себе)", "mv .git .git.x", "test -w ."),
    ]:
        machine.succeed(in_repo(control))
        status, _ = machine.execute(sandbox_repo(cmd))
        assert status != 0, f"AI-SBX-7: {label} должно отказывать изнутри песочницы"
    # Контроль для mv .git: снаружи то же переименование проходит (и откатывается).
    machine.succeed(in_repo("mv .git .git.x && mv .git.x .git"))
    # Ничего не сломалось и не появилось.
    machine.succeed(in_repo("test -d .git/hooks && test ! -e .git/hooks/evil && test ! -e .git.x && git status --short"))
    assert "evil" not in machine.succeed(in_repo("git config user.name")), "AI-SBX-7: config не должен измениться"

    # Кэш окружения у роли свой: запись изнутри не попадает в .direnv пользователя.
    machine.succeed(sandbox_repo("mkdir .direnv/inside-marker"))
    machine.fail(in_repo("test -e .direnv/inside-marker"))
    machine.succeed(f"ls {STATE}/direnv/*/inside-marker")

    # Отчёт лаунчера (AI-A12): чистая сессия — «без отклонений»; со сдвигами —
    # каждое перечислено, штатный коммит в текущую ветку — нет.
    machine.succeed(outside(f"agents-git snapshot {REPO} /home/agent/snap-clean"))
    clean = machine.succeed(outside(f"agents-git report {REPO} /home/agent/snap-clean 2>&1"))
    assert "без отклонений" in clean, f"отчёт чистой сессии: {clean!r}"

    machine.succeed(outside(f"agents-git snapshot {REPO} /home/agent/snap"))
    machine.succeed(sandbox_repo(
        "echo a > new.txt && git add new.txt && git commit -qm more "
        "&& git update-ref refs/heads/side HEAD~1 "
        "&& git branch fresh "
        "&& git update-index --skip-worktree README.md "
        "&& git replace HEAD~1 HEAD "
        "&& git init -q nested-repo "
        "&& echo changed > ignored.log "
        "&& touch .git/config.worktree"
    ))
    # Кэш direnv (как пересборка `.direnv` в долгоживущей песочнице, ADR-48) — не отклонение.
    machine.succeed(outside(f"mkdir -p {REPO}/.direnv && touch {REPO}/.direnv/flake-profile-x"))
    rep = machine.succeed(outside(f"agents-git report {REPO} /home/agent/snap 2>&1"))
    assert ".direnv" not in rep, f"кэш direnv не попадает в отчёт: {rep!r}"
    for want in [
        "refs/heads/side",
        "refs/heads/fresh",
        "флаг индекса",
        "README.md",
        "refs/replace",
        "nested-repo",
        "ignored.log",
        "config.worktree",
    ]:
        assert want in rep, f"AI-A12: в отчёте нет {want!r}: {rep!r}"
    assert "refs/heads/main" not in rep and "текущая ветка" not in rep, (
        f"AI-A12: коммит в текущую ветку не должен попадать в отчёт: {rep!r}"
    )

    # Каталог вне git: защита git не мешает, отчёт молчит.
    machine.succeed(sandbox("touch ok2"))
    assert machine.succeed(outside(f"agents-git report {PROJECT} /home/agent/snap 2>&1")).strip() == ""

    # --- AI-SBX-11 (ПРОВЕРИТЬ → ПРОВЕРЕНО для текущей конфигурации) ---------
    # Непривилегированные пользовательские пространства имён сейчас никто не
    # отключает (security/hardening ещё не существует, R9.1 из ROADMAP.md
    # должен повторить эту же проверку после его появления).
    machine.succeed("su - agent -c 'bwrap --unshare-user --unshare-pid --ro-bind / / true'")
  '';
}
