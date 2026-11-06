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
  sandboxExec = pkgs.callPackage ../modules/ai/_agents-tools-sandbox.nix { };
  gitIsolate = pkgs.callPackage ../modules/ai/_agents-tools-git-isolate.nix { };
  dshProfile = pkgs.callPackage ../modules/ai/_agents-tools-dsh-profile.nix {
    dshRole = "cost-autonomous";
  };
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

    environment.etc."dsh-profile-web.yml".source = dshProfile.web;
    environment.etc."dsh-profile-headless.yml".source = dshProfile.headless;

    environment.systemPackages = [
      sandboxExec
      pkgs.socat
      gitIsolate
      pkgs.coreutils
      pkgs.bubblewrap
      pkgs.git
      pkgs.direnv
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
    # Копия конфига шлюза с ключами провайдера (три копии из D17).
    fixture_file("/home/agent/.local/state/llm-gateway/config.json", "gw-config-marker")
    # Секреты sops: каталог 0751, файлы пользователя 0400 — как у sops-nix.
    machine.succeed("install -d -m751 /run/secrets && install -d -m751 /run/secrets/rendered")
    fixture_file("/run/secrets/outside-secret", "top-secret")
    fixture_file("/run/secrets/rendered/llm-gw-access-key-agent", "gw-access-key-marker")
    fixture_file("/run/secrets/rendered/llm-gw-config-agent.json", "gw-rendered-marker")
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
    fixture_file("/home/agent/.config/git/config", "git-marker", "0644")
    fixture_file("/home/agent/.config/direnv/direnvrc", "direnvrc-marker", "0644")
    fixture_file("/home/agent/.config/aider/aider.conf.yml", "aider-marker", "0644")
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
        ("ключ доступа к шлюзу 0400", "/run/secrets/rendered/llm-gw-access-key-agent", "gw-access-key-marker"),
        ("отрендеренный конфиг шлюза", "/run/secrets/rendered/llm-gw-config-agent.json", "gw-rendered-marker"),
        ("ключ расшифровки секретов", "/home/agent/.config/sops/age/keys.txt", "age-key-marker"),
        ("профиль браузера", "/home/agent/.mozilla/firefox/x.default/logins.json", "browser-marker"),
        ("состояние шлюза", "/home/agent/.local/state/llm-gateway/config.json", "gw-config-marker"),
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
    assert run <= {"current-system", "user"}, f"AI-SBX-1: лишнее в /run: {run}"
    assert sandbox_out("ls -A /run/user/2000").strip() == "", "XDG_RUNTIME_DIR роли должен быть пустым"
    assert sandbox_out("ls /run/user").split() == ["2000"], "в /run/user только каталог самой роли"
    # Сокет демона сборки — единственное, что нужно из хоста для nix внутри.
    sandbox_out("test -S /nix/var/nix/daemon-socket/socket")

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
        ("/home/agent/.config/git/config", "git-marker"),
        ("/home/agent/.config/direnv/direnvrc", "direnvrc-marker"),
    ]:
        assert marker in sandbox_out(f"cat {path}"), f"AI-SBX-2: {path} из белого списка должен читаться"
        status, _ = machine.execute(sandbox(f"touch {path}-w"))
        assert status != 0, f"AI-SBX-2: {path} из белого списка — только чтение"
    assert "aider-marker" in sandbox_out("cat /home/agent/.config/aider/aider.conf.yml", "--config aider")
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
        "/run/secrets/rendered/llm-gw-access-key-agent' "
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

    # NET-10/L-7: переменные прокси пробрасываются.
    out = sandbox_out(
        "sh -c 'echo p=$http_proxy n=$no_proxy'",
        env="http_proxy=http://127.0.0.1:1 no_proxy=localhost",
    )
    assert "p=http://127.0.0.1:1" in out and "n=localhost" in out, f"NET-10: прокси не проброшены: {out!r}"

    # §2.5 класс D: --app-path отдаёт приложению ЕГО каталог на запись.
    fixture_file("/home/agent/.appstate/sessions", "app-marker", "0644")
    assert "app-marker" in sandbox_out("cat /home/agent/.appstate/sessions", "--app-path /home/agent/.appstate")
    sandbox_out("touch /home/agent/.appstate/written", "--app-path /home/agent/.appstate")
    machine.succeed("test -e /home/agent/.appstate/written")
    status, out = machine.execute(
        sandbox("cat /home/agent/.ssh/id_ed25519", "--app-path /home/agent/.appstate")
    )
    assert status != 0 and "fake-ssh-key" not in out, "--app-path не открывает ничего, кроме переданного пути"

    # === AI-SBX-12: --home-rw (роль claude). Урезанный набор AI-A7 ============
    HRW = "--home-rw"
    assert "fake-ssh-key" in sandbox_out("cat /home/agent/.ssh/id_ed25519", HRW), (
        "--home-rw действительно открывает $HOME (принятый риск AI-SBX-12)"
    )
    sandbox_out("touch /home/agent/written-outside-project", HRW)
    machine.succeed("test -e /home/agent/written-outside-project")
    for label, path, marker in [
        ("секрет sops", "/run/secrets/outside-secret", "top-secret"),
        ("ключ доступа к шлюзу", "/run/secrets/rendered/llm-gw-access-key-agent", "gw-access-key-marker"),
        ("отрендеренный конфиг шлюза", "/run/secrets/rendered/llm-gw-config-agent.json", "gw-rendered-marker"),
        ("состояние шлюза (маска до R9.16)", "/home/agent/.local/state/llm-gateway/config.json", "gw-config-marker"),
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

    # === Политика профилей dsh (R9.14): встроенный поиск выключен ============
    for prof in ["web", "headless"]:
        text = machine.succeed(f"cat /etc/dsh-profile-{prof}.yml")
        for plugin in ["web-search-deepseek", "web-deepseek-api"]:
            assert f"- id: {plugin}\n  disabled: true" in text, f"dsh/{prof}: {plugin} должен быть выключен"
        assert "baseURL: @GATEWAY_URL@/anthropic" in text and "model: cost-autonomous" in text
    assert "- id: tool-web\n  config:\n    search: false" in machine.succeed("cat /etc/dsh-profile-headless.yml")

    # --- AI-SBX-7: отдельный клон на отдельной ветке вместо прямого доступа
    # к чекауту пользователя; push по умолчанию запрещён; ветка пользователя
    # не трогается (AI-A12) --------------------------------------------------
    machine.succeed(
        "su - agent -c "
        "'git config --global user.email t@t && git config --global user.name t'"
    )
    machine.succeed(
        "su - agent -c "
        "'install -d /home/agent/proj-git "
        "&& cd /home/agent/proj-git "
        "&& git init -q "
        "&& echo hi > README.md && git add . && git commit -qm init'"
    )
    user_branch_before = machine.succeed(
        "su - agent -c 'git -C /home/agent/proj-git branch --show-current'"
    ).strip()

    clone_path = machine.succeed(
        "su - agent -c "
        "'agents-git-isolate dsh /home/agent/state /home/agent/proj-git'"
    ).strip()
    assert clone_path.startswith("/home/agent/state/repos/"), (
        f"agents-git-isolate должен вернуть путь внутри state-dir, получено: {clone_path!r}"
    )

    agent_branch = machine.succeed(
        f"su - agent -c 'git -C {clone_path} branch --show-current'"
    ).strip()
    assert agent_branch.startswith("agent/dsh/"), (
        f"клон должен быть на отдельной ветке agent/<роль>/<метка>, получено: {agent_branch!r}"
    )
    assert agent_branch != user_branch_before, "ветка агента не должна совпадать с веткой пользователя"

    user_branch_after = machine.succeed(
        "su - agent -c 'git -C /home/agent/proj-git branch --show-current'"
    ).strip()
    assert user_branch_after == user_branch_before, (
        "AI-SBX-7: создание клона агента не должно переключать ветку исходного репозитория"
    )

    # push из клона агента — по умолчанию запрещён (pre-push хук).
    machine.succeed(
        f"su - agent -c 'echo x >> {clone_path}/README.md "
        f"&& git -C {clone_path} commit -qam x'"
    )
    status, out = machine.execute(f"su - agent -c 'git -C {clone_path} push origin HEAD 2>&1'")
    assert status != 0 and "AI-SBX-7" in out, (
        f"AI-SBX-7: push из клона агента должен быть заблокирован, получено: {out!r}"
    )

    # Повторный вызов для того же (роль, репозиторий) переиспользует клон —
    # не плодит его на каждый запуск.
    clone_path_2 = machine.succeed(
        "su - agent -c "
        "'agents-git-isolate dsh /home/agent/state /home/agent/proj-git'"
    ).strip()
    assert clone_path_2 == clone_path, "повторный запуск должен переиспользовать тот же клон"

    # Клон репозитория без коммитов: повторный запуск не падает, пока источник
    # пуст, и подхватывает коммиты, когда они появились.
    isolate_empty = (
        "su - agent -c "
        "'agents-git-isolate dsh /home/agent/state /home/agent/proj-empty'"
    )
    machine.succeed("su - agent -c 'git init -q /home/agent/proj-empty'")
    empty_clone = machine.succeed(isolate_empty).strip()
    empty_branch = machine.succeed(
        f"su - agent -c 'git -C {empty_clone} symbolic-ref --short HEAD'"
    ).strip()
    assert empty_branch.startswith("agent/dsh/"), (
        f"клон пустого репозитория должен быть на ветке агента, получено: {empty_branch!r}"
    )
    assert machine.succeed(isolate_empty).strip() == empty_clone, (
        "пока источник пуст, повторный запуск должен вернуть тот же клон"
    )

    # Неотслеживаемый файл агента не затирается: отказ с понятной причиной.
    machine.succeed(
        "su - agent -c "
        "'cd /home/agent/proj-empty "
        "&& echo hi > README.md && git add . && git commit -qm init'"
    )
    machine.succeed(f"su - agent -c 'echo agent > {empty_clone}/README.md'")
    status, out = machine.execute(isolate_empty + " 2>&1")
    assert status != 0 and "мешающие файлы" in out, (
        f"конфликт с файлом агента должен приводить к отказу, получено: {out!r}"
    )
    assert machine.succeed(f"su - agent -c 'cat {empty_clone}/README.md'").strip() == "agent", (
        "неотслеживаемый файл агента не должен быть перезаписан"
    )

    machine.succeed(f"su - agent -c 'rm {empty_clone}/README.md'")
    assert machine.succeed(isolate_empty).strip() == empty_clone, (
        "после появления коммитов клон должен остаться тем же"
    )
    assert machine.succeed(
        f"su - agent -c 'git -C {empty_clone} symbolic-ref --short HEAD'"
    ).strip() == empty_branch, "ветка агента должна сохраниться"
    source_head = machine.succeed("su - agent -c 'git -C /home/agent/proj-empty rev-parse HEAD'")
    clone_head = machine.succeed(f"su - agent -c 'git -C {empty_clone} rev-parse HEAD'")
    assert clone_head == source_head, "клон должен подхватить коммит источника"
    machine.succeed(f"su - agent -c 'test -f {empty_clone}/README.md'")

    # Каталог вне git — AI-SBX-7 неприменим, путь возвращается как есть.
    passthrough = machine.succeed(
        "su - agent -c 'agents-git-isolate dsh /home/agent/state /home/agent/project'"
    ).strip()
    assert passthrough == "/home/agent/project", (
        "вне git-репозитория agents-git-isolate не должен подменять каталог"
    )

    # --- AI-SBX-11 (ПРОВЕРИТЬ → ПРОВЕРЕНО для текущей конфигурации) ---------
    # Непривилегированные пользовательские пространства имён сейчас никто не
    # отключает (security/hardening ещё не существует, R9.1 из ROADMAP.md
    # должен повторить эту же проверку после его появления).
    machine.succeed("su - agent -c 'bwrap --unshare-user --unshare-pid --ro-bind / / true'")
  '';
}
