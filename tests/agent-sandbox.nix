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

    environment.systemPackages = [
      sandboxExec
      gitIsolate
      pkgs.coreutils
      pkgs.bubblewrap
      pkgs.git
      pkgs.direnv
    ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # --- Фикстура: секреты/ключи/маркер репозитория вне project-dir/state-dir
    machine.succeed("install -d -m700 -o agent -g agent /home/agent/.ssh")
    machine.succeed(
        "echo fake-ssh-key > /home/agent/.ssh/id_ed25519 "
        "&& chown agent:agent /home/agent/.ssh/id_ed25519 "
        "&& chmod 600 /home/agent/.ssh/id_ed25519"
    )
    machine.succeed("install -d -m755 -o agent -g agent /home/agent/nixos-config")
    machine.succeed(
        "echo repo-marker > /home/agent/nixos-config/flake.nix "
        "&& chown agent:agent /home/agent/nixos-config/flake.nix"
    )
    machine.succeed("install -d -m700 /run/secrets")
    machine.succeed("echo top-secret > /run/secrets/outside-secret")
    machine.succeed("install -d -m755 -o agent -g agent /home/agent/project")
    machine.succeed("install -d -m755 -o agent -g agent /home/agent/state")
    # Поддельный docker.sock (AI-SBX-10): обычного файла с меткой достаточно,
    # чтобы проверить маскировку пути — без реального AF_UNIX-слушателя.
    machine.succeed("echo docker-socket-marker > /run/docker.sock")

    # --- AI-A7: секреты/ключи/репозиторий недостижимы из песочницы ----------
    for label, path in [
        ("ssh-ключ", "/home/agent/.ssh/id_ed25519"),
        ("репозиторий nixos-config", "/home/agent/nixos-config/flake.nix"),
        ("секрет вне sandbox", "/run/secrets/outside-secret"),
    ]:
        status, _ = machine.execute(
            "su - agent -c "
            f"'agents-sandbox-exec /home/agent/project /home/agent/state online -- cat {path}'"
        )
        assert status != 0, f"AI-A7: {label} не должен быть читаем из песочницы ({path})"

    # --- AI-SBX-10: докеровский сокет замаскирован, не исходное содержимое --
    _, out = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online -- cat /run/docker.sock'"
    )
    assert "docker-socket-marker" not in out, (
        "AI-SBX-10: путь /run/docker.sock должен быть замаскирован — "
        "исходное содержимое не должно быть видно из песочницы"
    )

    # --- AI-SBX-2: запись возможна только в project-dir и state-dir ---------
    machine.succeed(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online -- "
        "touch /home/agent/project/ok'"
    )
    machine.succeed("test -e /home/agent/project/ok")

    status, _ = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online -- "
        "touch /etc/should-not-exist'"
    )
    assert status != 0, "AI-SBX-2: запись вне project-dir/state-dir должна быть запрещена"
    machine.fail("test -e /etc/should-not-exist")

    # --- AI-A8: «вредоносный» файл инструкций не достаёт секрет -------------
    machine.succeed(
        "echo 'cat /home/agent/.ssh/id_ed25519' > /home/agent/project/malicious.sh "
        "&& chown agent:agent /home/agent/project/malicious.sh"
    )
    status, out = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online -- "
        "sh /home/agent/project/malicious.sh'"
    )
    assert status != 0 and "fake-ssh-key" not in out, (
        "AI-A8: выполнение файла инструкций изнутри проекта не должно доставать "
        "секрет из-за пределов песочницы — граница держится независимо от "
        "содержимого проектных файлов (AI-SBX-9)"
    )

    # --- AI-SBX-6 (fail-closed): ошибка bwrap не исполняет целевую команду --
    status, _ = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/no-such-project /home/agent/state online -- "
        "touch /home/agent/state/should-not-be-created'"
    )
    assert status != 0, "AI-SBX-6: несуществующий project-dir должен останавливать запуск до exec"
    machine.fail("test -e /home/agent/state/should-not-be-created")

    # --- AI-AGT-3: ~/.config доступен на чтение (конфиги ролей из dotfiles),
    # --env прокидывает путь конфига внутрь песочницы (CLAUDE_CONFIG_DIR и
    # аналоги у agent-launcher) ------------------------------------------
    machine.succeed(
        "install -d -m755 -o agent -g agent /home/agent/.config/claude-code "
        "&& echo config-marker > /home/agent/.config/claude-code/settings.json "
        "&& chown agent:agent /home/agent/.config/claude-code/settings.json"
    )
    _, out = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online -- "
        "cat /home/agent/.config/claude-code/settings.json'"
    )
    assert "config-marker" in out, (
        "AI-AGT-3: конфиг роли из dotfiles (~/.config) должен быть читаем из песочницы"
    )

    _, out = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online "
        "--env CLAUDE_CONFIG_DIR=/home/agent/.config/claude-code -- "
        "printenv CLAUDE_CONFIG_DIR'"
    )
    assert "/home/agent/.config/claude-code" in out, (
        "--env должен доносить путь конфига роли внутрь песочницы как переменную"
    )

    # --- AI-SBX-2, регрессия: project-dir = $HOME открывал весь домашний
    # каталог (--bind перекрывал --tmpfs). Проверяем отказ, а не «не видно»:
    # сам запуск должен быть запрещён, и целевая команда не исполниться.
    for label, pdir in [
        ("домашний каталог", "/home/agent"),
        ("предок домашнего каталога", "/home"),
        ("корень", "/"),
    ]:
        status, _ = machine.execute(
            "su - agent -c "
            f"'agents-sandbox-exec {pdir} /home/agent/state online -- "
            "touch /home/agent/state/breach'"
        )
        assert status != 0, (
            f"AI-SBX-2: project-dir = {label} ({pdir}) должен быть запрещён — "
            "иначе bind перекрывает tmpfs и агент получает настоящий $HOME"
        )
        machine.fail("test -e /home/agent/state/breach")

    # Контрольная проверка того же сценария с другой стороны: ssh-ключ лежит
    # в /home/agent, и при project-dir = /home/agent он стал бы читаемым.
    status, out = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent /home/agent/state online -- "
        "cat /home/agent/.ssh/id_ed25519'"
    )
    assert status != 0 and "fake-ssh-key" not in out, (
        "AI-SBX-2: запуск с project-dir = $HOME не должен давать доступ к ключам"
    )

    # --- NET-10/L-7: переменные прокси пробрасываются в песочницу (в режиме
    # M1 без них агент уходит мимо туннеля — ПРОВЕРЕНО живьём: 403) ---------
    _, out = machine.execute(
        "su - agent -c "
        "'http_proxy=http://127.0.0.1:1 no_proxy=localhost "
        "agents-sandbox-exec /home/agent/project /home/agent/state online -- "
        "sh -c \"echo p=\\$http_proxy n=\\$no_proxy\"'"
    )
    assert "p=http://127.0.0.1:1" in out and "n=localhost" in out, (
        f"NET-10: переменные прокси должны попадать в окружение агента, получено: {out!r}"
    )

    # --- §2.5 класс D: --app-path отдаёт приложению ЕГО каталог на запись,
    # не ослабляя остального (сессии/MCP/плагины агента живут там) ----------
    machine.succeed(
        "install -d -m755 -o agent -g agent /home/agent/.appstate "
        "&& echo app-marker > /home/agent/.appstate/sessions "
        "&& chown agent:agent /home/agent/.appstate/sessions"
    )
    _, out = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online "
        "--app-path /home/agent/.appstate -- cat /home/agent/.appstate/sessions'"
    )
    assert "app-marker" in out, (
        "§2.5 класс D: каталог приложения, переданный --app-path, должен быть читаем"
    )
    machine.succeed(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online "
        "--app-path /home/agent/.appstate -- touch /home/agent/.appstate/written'"
    )
    machine.succeed("test -e /home/agent/.appstate/written")

    # ...и при этом ключи/секреты по-прежнему недостижимы: --app-path не
    # открывает домашний каталог целиком (регрессия на случай, если список
    # когда-нибудь подменят каталогом-предком).
    status, out = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online "
        "--app-path /home/agent/.appstate -- cat /home/agent/.ssh/id_ed25519'"
    )
    assert status != 0 and "fake-ssh-key" not in out, (
        "AI-SBX-2: --app-path не должен открывать ничего, кроме переданного пути"
    )

    # HOME внутри — настоящий путь, но пустой tmpfs (иначе `~/...` приложения
    # не совпал бы с --app-path; ПРОВЕРЕНО живьём).
    _, out = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online -- "
        "sh -c \"echo HOME=\\$HOME\"'"
    )
    assert "HOME=/home/agent" in out, f"HOME внутри песочницы должен быть настоящим путём, получено: {out!r}"

    # --- AI-SBX-4: база разрешений direnv видна внутри (иначе `.envrc is
    # blocked` и агент не стартует в любом проекте с .envrc) ----------------
    machine.succeed(
        "install -d -m755 -o agent -g agent /home/agent/.local/share/direnv/allow "
        "&& echo allow-marker > /home/agent/.local/share/direnv/allow/test "
        "&& chown agent:agent /home/agent/.local/share/direnv/allow/test"
    )
    _, out = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online -- "
        "cat /home/agent/.local/share/direnv/allow/test'"
    )
    assert "allow-marker" in out, (
        "AI-SBX-4: база разрешений direnv должна быть читаема внутри песочницы"
    )
    # ...но только она: соседние каталоги в ~/.local/share остаются скрытыми.
    machine.succeed(
        "install -d -m755 -o agent -g agent /home/agent/.local/share/other "
        "&& echo other-marker > /home/agent/.local/share/other/data "
        "&& chown agent:agent /home/agent/.local/share/other/data"
    )
    status, out = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online -- "
        "cat /home/agent/.local/share/other/data'"
    )
    assert status != 0 and "other-marker" not in out, (
        "AI-SBX-2: виден должен быть только каталог direnv, не весь ~/.local/share"
    )

    # --- AI-SBX-12: ослабленный режим --home-rw (роль claude по решению
    # пользователя). Проверяем И то, что он действительно даёт доступ, И то,
    # что он НЕ отменяет остальных границ — иначе «ослабление» незаметно
    # превратится в полное отсутствие песочницы.
    machine.succeed(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online --home-rw -- "
        "cat /home/agent/.ssh/id_ed25519'"
    )
    machine.succeed(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online --home-rw -- "
        "touch /home/agent/written-outside-project'"
    )
    machine.succeed("test -e /home/agent/written-outside-project")

    # ...но запись ВНЕ $HOME остаётся запрещённой,
    status, _ = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online --home-rw -- "
        "touch /etc/should-not-exist-homerw'"
    )
    assert status != 0, "AI-SBX-12: --home-rw не должен давать запись вне $HOME"
    machine.fail("test -e /etc/should-not-exist-homerw")

    # ...сокет контейнерного рантайма — замаскированным (AI-SBX-10),
    _, out = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec /home/agent/project /home/agent/state online --home-rw -- "
        "cat /run/docker.sock'"
    )
    assert "docker-socket-marker" not in out, (
        "AI-SBX-10 действует и в --home-rw: сокет рантайма остаётся замаскированным"
    )

    # ...а корень `/` в роли project-dir — запрещённым и здесь.
    status, _ = machine.execute(
        "su - agent -c "
        "'agents-sandbox-exec / /home/agent/state online --home-rw -- true'"
    )
    assert status != 0, "project-dir = / запрещён в любом режиме"

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
