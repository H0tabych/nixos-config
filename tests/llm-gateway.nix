# Проверка свойства (STRUCTURE 5.1): шлюз (ADR-45, ADR-051) — AI-A14, AI-A6 (права),
# матрица ключей «агент × режим» (AI-GW-4), локальные роли (AI-GW-2), MCP-шлюз (AI-GW-14).
# Конфиг шлюза не показывает, что делает настоящий бинарник Bifrost с правами ключей, поэтому
# тест запускает ТОТ ЖЕ юнит (`modules/ai/_llm-gateway-service.nix`) и ТОТ ЖЕ шаблон
# (`_llm-gateway-config.nix`), что и хост, с реальным бинарником, а вместо локального
# инференса — фальшивый HTTP-сервер на loopback (запросы пишутся в журнал: видно, куда дошёл
# запрос и под какой моделью). Облачных провайдеров в шлюзе нет: их отсутствие — тоже проверка.
{
  pkgs,
  lib,
  ...
}:
let
  buildConfig = import ../modules/ai/_llm-gateway-config.nix { inherit lib; };
  pkg = pkgs.callPackage ../modules/ai/_llm-gateway-package.nix { };

  pricingFile = pkgs.writeText "pricing.json" "{}";
  agents = {
    dsh = {
      localRoles = [ "local-chat" ];
      mcp = [ ];
    };
    localonly = {
      localRoles = [ "local-chat" ];
      mcp = [ ];
    };
    # AI-GW-14: агент только с инструментами (как claude по подписке): ролей нет.
    mcpagent = {
      localRoles = [ ];
      mcp = [
        "fake-http"
        "fake-stdio"
        "empty-secret"
        "fake-file"
        "missing-file"
      ];
    };
  };
  # MCP-шлюз (AI-GW-14): фальшивый http-сервер (9002, с секретом в заголовке), фальшивый stdio-сервер
  # (секрет и несекретная переменная доходят до него через обёртку) и сервер с ПУСТЫМ секретом —
  # его вычёркивает служба, юнит не `failed`.
  mcpPolicy =
    lib.mapAttrs
      (
        _: s:
        {
          command = null;
          args = [ ];
          env = { };
          url = null;
          headers = { };
          secret = false;
          secretEnv = null;
          secretHeader = "Authorization";
          secretPrefix = "Bearer ";
          secretHomeFile = null;
        }
        // s
      )
      {
        fake-http = {
          type = "http";
          url = "http://127.0.0.1:9002/mcp";
          secret = true;
        };
        fake-stdio = {
          type = "stdio";
          command = "${fakeMcpStdio}";
          env.FAKE_PLAIN = "plain-value";
          secret = true;
          secretEnv = "FAKE_SECRET";
        };
        # Секрет — файл в домашнем каталоге пользователя (решение владельца), а не sops.
        fake-file = {
          type = "stdio";
          command = "${fakeMcpStdio}";
          secret = true;
          secretEnv = "FAKE_SECRET";
          secretHomeFile = "mcp-token-file";
        };
        # Файла нет — сервер вычёркивается, служба стартует (AI-GW-9).
        missing-file = {
          type = "stdio";
          command = "${fakeMcpStdio}";
          secret = true;
          secretEnv = "FAKE_SECRET";
          secretHomeFile = "no-such-file";
        };
        empty-secret = {
          type = "stdio";
          command = "${fakeMcpStdio}";
          secret = true;
          secretEnv = "FAKE_SECRET";
        };
      };
  mcpBuild = import ../modules/ai/_llm-gateway-mcp.nix { inherit lib pkgs; } {
    policy = mcpPolicy;
    inherit agents;
  };
  template = buildConfig {
    inherit agents;
    mcp = mcpBuild;
    inference = {
      host = "127.0.0.1";
      port = 9001;
    };
    localRoles.local-chat = "local-model";
    # Справочник цен — пустой файл, как у хоста. ВМ без сети: справочник параметров моделей — тоже
    # из пустого файла (иначе первый старт грузит его с getbifrost.ai).
    pricingUrl = "file://${pricingFile}";
    frameworkOverride.framework.pricing.model_parameters_url = "file://${pkgs.writeText "model-params.json" "{}"}";
  };

  service = import ../modules/ai/_llm-gateway-service.nix {
    inherit
      lib
      pkgs
      pkg
      template
      ;
    user = "alice";
    group = "alice";
    port = 11501;
    keyIds = [
      "dsh-online"
      "dsh-offline"
      "localonly-online"
      "localonly-offline"
      "mcpagent-online"
      "mcpagent-offline"
    ];
    mcpSecrets = map (
      s:
      s
      // {
        src = if s.homeFile != null then "/home/alice/${s.homeFile}" else "/etc/test-secrets/mcp-${s.id}";
      }
    ) mcpBuild.secrets;
  };

  fakeMcpStdio = pkgs.writers.writePython3 "fake-mcp-stdio" { doCheck = false; } ''
    import json
    import os
    import sys

    for line in sys.stdin:
        if not line.strip():
            continue
        m = json.loads(line)
        mid, method = m.get("id"), m.get("method")
        if mid is None:
            continue
        if method == "initialize":
            res = {"protocolVersion": m["params"]["protocolVersion"],
                   "capabilities": {"tools": {}},
                   "serverInfo": {"name": "fake-stdio", "version": "0"}}
        elif method == "tools/list":
            res = {"tools": [{"name": "whoami", "description": "env",
                              "inputSchema": {"type": "object", "properties": {}}}]}
        elif method == "tools/call":
            res = {"content": [{"type": "text", "text": json.dumps({
                "secret": os.environ.get("FAKE_SECRET"),
                "plain": os.environ.get("FAKE_PLAIN"),
                "home": os.environ.get("HOME"),
            })}]}
        else:
            res = {}
        sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": res}) + "\n")
        sys.stdout.flush()
  '';

  # Фальшивый удалённый MCP-сервер (streamable HTTP): пишет заголовок Authorization в журнал.
  fakeMcpHttp = pkgs.writers.writePython3 "fake-mcp-http" { doCheck = false; } ''
    import json
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


    class H(BaseHTTPRequestHandler):
        def do_POST(self):
            n = int(self.headers.get("Content-Length") or 0)
            m = json.loads(self.rfile.read(n) or b"{}")
            with open("/var/log/fake-mcp-http.log", "a") as f:
                f.write(json.dumps({"method": m.get("method"),
                                    "auth": self.headers.get("Authorization")}) + "\n")
            mid, method = m.get("id"), m.get("method")
            if mid is None:
                self.send_response(202)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if method == "initialize":
                res = {"protocolVersion": m["params"]["protocolVersion"],
                       "capabilities": {"tools": {}},
                       "serverInfo": {"name": "fake-http", "version": "0"}}
            elif method == "tools/list":
                res = {"tools": [{"name": "ping", "description": "p",
                                  "inputSchema": {"type": "object", "properties": {}}}]}
            elif method == "tools/call":
                res = {"content": [{"type": "text", "text": "pong"}]}
            else:
                res = {}
            out = json.dumps({"jsonrpc": "2.0", "id": mid, "result": res}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(out)))
            self.end_headers()
            self.wfile.write(out)

        def log_message(self, *a):
            pass


    ThreadingHTTPServer(("127.0.0.1", 9002), H).serve_forever()
  '';

  fakeProvider = pkgs.writers.writePython3 "fake-provider" { doCheck = false; } ''
    import json
    import threading
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    LOG = "/var/log/fake-provider.jsonl"


    def make(port):
        class H(BaseHTTPRequestHandler):
            def reply(self):
                n = int(self.headers.get("Content-Length") or 0)
                body = self.rfile.read(n).decode() if n else ""
                try:
                    parsed = json.loads(body)
                    model = parsed.get("model")
                except Exception:
                    parsed, model = {}, None
                with open(LOG, "a") as f:
                    f.write(json.dumps({
                        "port": port, "path": self.path, "model": model,
                        "auth": self.headers.get("Authorization"),
                        "keys": sorted(parsed),
                        "tools": [t.get("function", {}).get("name") for t in parsed.get("tools") or []],
                        "body": parsed,
                    }) + "\n")
                out = json.dumps({
                    "id": "x", "object": "chat.completion", "created": 0, "model": model,
                    "choices": [{"index": 0, "finish_reason": "stop",
                                 "message": {"role": "assistant", "content": "ok"}}],
                    "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
                }).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(out)))
                self.end_headers()
                self.wfile.write(out)

            do_POST = reply
            do_GET = reply

            def log_message(self, *a):
                pass

        return H


    for p in (9001,):
        threading.Thread(
            target=ThreadingHTTPServer(("127.0.0.1", p), make(p)).serve_forever, daemon=True
        ).start()
    threading.Event().wait()
  '';
in
assert template.governance.budgets == [ ];
assert builtins.attrNames template.providers == [ "local-inference" ];
assert template.framework.pricing.pricing_url == "file://${pricingFile}";
pkgs.testers.runNixOSTest {
  name = "llm-gateway";

  nodes.machine = {
    users.groups = {
      alice.gid = 2001;
      bob.gid = 2002;
    };
    users.users = {
      alice = {
        isNormalUser = true;
        uid = 2001;
        group = "alice";
      };
      bob = {
        isNormalUser = true;
        uid = 2002;
        group = "bob";
      };
    };

    environment.systemPackages = [
      pkgs.curl
      pkgs.jq
    ];

    environment.etc = {
      "test-secrets/mcp-fake-http" = {
        text = "fake-mcp-token\n";
        mode = "0400";
      };
      "test-secrets/mcp-fake-stdio" = {
        text = "fake-stdio-secret\n";
        mode = "0400";
      };
      # Пустой секрет сервера MCP: клиент вычёркивается, служба стартует (AI-GW-9, AI-GW-14).
      "test-secrets/mcp-empty-secret" = {
        text = "";
        mode = "0400";
      };
    };

    systemd.tmpfiles.rules = [ "f /home/alice/mcp-token-file 0600 alice alice - file-secret" ];

    systemd.services.fake-mcp-http = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = fakeMcpHttp;
    };

    systemd.services.fake-provider = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = fakeProvider;
    };

    systemd.services.llm-gateway-alice = service // {
      after = service.after ++ [
        "fake-provider.service"
        "fake-mcp-http.service"
      ];
    };
  };

  testScript = ''
    import json
    import shlex

    PORT = 11501
    LOG = "/var/log/fake-provider.jsonl"
    KEYS = "/run/llm-gateway/alice"

    machine.wait_for_unit("fake-provider.service")
    machine.wait_for_unit("fake-mcp-http.service")
    machine.wait_for_unit("llm-gateway-alice.service")
    machine.wait_for_open_port(PORT)


    def key(name):
        return machine.succeed(f"cat {KEYS}/{name}").strip()


    def provider_log():
        out = machine.succeed(f"cat {LOG} 2>/dev/null || true")
        return [json.loads(l) for l in out.splitlines() if l.strip()]


    def ask(model, token):
        """Возвращает (код ответа, тело) запроса chat/completions."""
        auth = f"-H 'Authorization: Bearer {token}'" if token else ""
        body = json.dumps({"model": model, "messages": [{"role": "user", "content": "hi"}]})
        out = machine.succeed(
            f"curl -s -m 20 -o /tmp/out -w '%{{http_code}}' {auth} "
            f"-H 'Content-Type: application/json' -d {shlex.quote(body)} "
            f"http://127.0.0.1:{PORT}/v1/chat/completions; echo; cat /tmp/out"
        )
        code, _, rest = out.partition("\n")
        return int(code), rest


    def denied(model, token, why):
        before = len(provider_log())
        code, body = ask(model, token)
        assert code != 200, f"{why}: ожидался отказ, получен 200 ({body})"
        assert len(provider_log()) == before, f"{why}: запрос дошёл до провайдера"


    # --- AI-A14: служба жива без облачных ключей (их в шлюзе нет, ADR-051).
    machine.succeed("systemctl is-active llm-gateway-alice.service")

    # --- Ключи: файлы пользователя, права, постоянство.
    for name in ["dsh-online", "dsh-offline", "localonly-online", "localonly-offline"]:
        assert key(name).startswith("sk-bf-"), name
    assert len({key(n) for n in ["dsh-online", "dsh-offline", "localonly-online", "localonly-offline"]}) == 4

    # --- Локальная роль доступна обоим режимам.
    for name in ["dsh-online", "dsh-offline", "localonly-online", "localonly-offline"]:
        code, body = ask("local-chat", key(name))
        assert code == 200, (name, code, body)
        last = provider_log()[-1]
        assert (last["port"], last["model"]) == (9001, "local-model"), last

    # --- Матрица запретов (AI-GW-4): до локального бэкенда запрос не доходит.
    # Облачных ролей и моделей провайдера в шлюзе нет (ADR-051) — любая такая модель отклоняется.
    denied("cost-autonomous", key("dsh-online"), "облачной роли в шлюзе нет")
    denied("deepseek-v4-pro", key("dsh-online"), "модели провайдера в шлюзе нет")
    denied("local-chat", key("mcpagent-online"), "локальная роль не из перечня агента")
    denied("local-chat", None, "запрос без ключа")
    denied("local-chat", "sk-bf-wrong", "чужой ключ")
    denied("unknown-model", key("dsh-online"), "модель вне перечней")

    # --- Управляющий API без учётных данных закрыт.
    code = machine.succeed(
        f"curl -s -o /dev/null -w '%{{http_code}}' http://127.0.0.1:{PORT}/api/providers"
    ).strip()
    assert code in ("401", "403"), f"management-API без входа: {code}"

    # --- AI-A6 (права): состояние службы и секреты серверов MCP недоступны пользователю.
    machine.succeed(f"su alice -c 'cat {KEYS}/dsh-online'")
    machine.fail("su alice -c 'cat /etc/test-secrets/mcp-fake-stdio'")
    machine.fail("su alice -c 'ls /var/lib/private/llm-gateway-alice'")
    machine.fail("su alice -c 'ls /var/lib/llm-gateway-alice'")
    assert machine.succeed(f"ls {KEYS}").split() == sorted(
        ["dsh-online", "dsh-offline", "localonly-online", "localonly-offline",
         "mcpagent-online", "mcpagent-offline"]
    ), "пользователю публикуются только ключи доступа"
    # Другой пользователь (без ml, USER-7) не читает чужие ключи и каталог.
    machine.fail(f"su bob -c 'cat {KEYS}/dsh-online'")
    machine.fail(f"su bob -c 'ls {KEYS}'")
    # Учётные данные управляющего API не публикуются пользователю.
    machine.fail(f"test -e {KEYS}/admin-pass")

    # --- Права ключа в самом конфиге (root видит): инструменты пусты, облака нет (ADR-051).
    cfg = json.loads(machine.succeed("cat /var/lib/private/llm-gateway-alice/config.json"))
    vks = {v["id"]: v for v in cfg["governance"]["virtual_keys"]}
    assert all(v["mcp_configs"] == [] for k, v in vks.items() if k != "mcpagent-online")
    assert all(not v["allow_all_providers"] for v in vks.values())
    assert list(cfg["providers"]) == ["local-inference"], f"в шлюзе только локальный бэкенд: {list(cfg['providers'])}"
    assert cfg["governance"]["budgets"] == [], "бюджетов нет (ADR-051)"
    # Справочник цен — пустой файл из хранилища, а не загрузка поставщика (AI-GW-13).
    pricing_url = cfg["framework"]["pricing"]["pricing_url"]
    assert pricing_url.startswith("file:///nix/store/"), pricing_url
    assert json.loads(machine.succeed(f"cat {pricing_url[len('file://'):]}")) == {}

    # --- MCP-шлюз (AI-GW-14): ключ видит только разрешённые ему инструменты.
    def mcp(method, token, params=None):
        """JSON-RPC к /mcp; возвращает (код ответа, разобранное тело или текст)."""
        hdr = f"-H 'x-bf-vk: {token}'" if token else ""
        body = {"jsonrpc": "2.0", "id": 1, "method": method}
        if params:
            body["params"] = params
        out = machine.succeed(
            f"curl -s -m 30 -o /tmp/mcp -w '%{{http_code}}' {hdr} -H 'Content-Type: application/json' "
            f"-d {shlex.quote(json.dumps(body))} http://127.0.0.1:{PORT}/mcp; echo; cat /tmp/mcp"
        )
        code, _, rest = out.partition("\n")
        try:
            return int(code), json.loads(rest)
        except Exception:
            return int(code), rest

    def mcp_tools(token):
        code, body = mcp("tools/list", token)
        assert code == 200, (code, body)
        return sorted(t["name"] for t in body["result"]["tools"])

    machine.wait_until_succeeds(
        "test $(curl -s -m 10 -H 'x-bf-vk: " + key("mcpagent-online") + "' "
        "-H 'Content-Type: application/json' "
        "-d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}' "
        f"http://127.0.0.1:{PORT}/mcp | jq '.result.tools | length') -ge 2",
        timeout=90,
    )
    names = mcp_tools(key("mcpagent-online"))
    print("MCP, инструменты ключа mcpagent-online:", names)
    assert any(n.startswith("fake_http") for n in names), names
    assert any(n.startswith("fake_stdio") for n in names), names
    assert not any(n.startswith("empty_secret") for n in names), f"сервер без секрета вычеркнут: {names}"
    assert not any(n.startswith("missing_file") for n in names), f"сервер без файла секрета вычеркнут: {names}"
    assert any(n.startswith("fake_file") for n in names), f"сервер с секретом из домашнего файла: {names}"
    # Остальные ключи инструментов не видят (по умолчанию запрещено всё; offline — без инструментов).
    for other in ["mcpagent-offline", "dsh-online", "dsh-offline", "localonly-online"]:
        code, body = mcp("tools/list", key(other))
        shown = body["result"]["tools"] if code == 200 and isinstance(body, dict) else []
        assert shown == [], f"{other} видит инструменты: {code} {body}"
    code, body = mcp("tools/list", None)
    assert code in (401, 403), f"/mcp без ключа: {code} {body}"
    code, body = mcp("tools/list", "sk-bf-wrong")
    assert code in (401, 403), f"/mcp с чужим ключом: {code} {body}"
    # Вызов недоступного ключу инструмента — отказ.
    code, body = mcp("tools/call", key("dsh-online"), {"name": "fake_stdio_whoami", "arguments": {}})
    assert not (code == 200 and isinstance(body, dict) and "result" in body and not body["result"].get("isError")), (
        f"dsh-online вызвал чужой инструмент: {code} {body}"
    )

    # stdio: секрет из учётных данных и несекретная переменная дошли до сервера через обёртку;
    # HOME — в состоянии службы (DynamicUser).
    wid = [n for n in names if n.startswith("fake_stdio")][0]
    code, body = mcp("tools/call", key("mcpagent-online"), {"name": wid, "arguments": {}})
    assert code == 200, (code, body)
    seen = json.loads(body["result"]["content"][0]["text"])
    assert seen["secret"] == "fake-stdio-secret" and seen["plain"] == "plain-value", seen
    assert seen["home"].startswith("/var/lib/"), seen

    fid = [n for n in names if n.startswith("fake_file")][0]
    code, body = mcp("tools/call", key("mcpagent-online"), {"name": fid, "arguments": {}})
    assert code == 200, (code, body)
    assert json.loads(body["result"]["content"][0]["text"])["secret"] == "file-secret", body

    # http: токен сервера подставлен службой в заголовок; у агента его нет.
    hid = [n for n in names if n.startswith("fake_http")][0]
    code, body = mcp("tools/call", key("mcpagent-online"), {"name": hid, "arguments": {}})
    assert code == 200 and body["result"]["content"][0]["text"] == "pong", (code, body)
    assert "Bearer fake-mcp-token" in machine.succeed("cat /var/log/fake-mcp-http.log"), "заголовок Authorization"
    machine.fail(f"grep -rE 'fake-mcp-token|fake-stdio-secret' {KEYS}")
    cfg = json.loads(machine.succeed("cat /var/lib/private/llm-gateway-alice/config.json"))
    assert not {"empty_secret", "missing_file"} & {c["name"] for c in cfg["mcp"]["client_configs"]}, "клиент без секрета не вычеркнут"
    machine.succeed("systemctl is-active llm-gateway-alice.service")
    # Секрет stdio-сервера не попал ни в конфиг, ни в argv процессов.
    assert "fake-stdio-secret" not in json.dumps(cfg) and "file-secret" not in json.dumps(cfg), "секрет stdio-сервера в конфиге шлюза"
    # Копии секретов в состоянии службы недоступны пользователю (AI-A6).
    machine.fail("su alice -c 'ls /var/lib/private/llm-gateway-alice/mcp-secrets'")
    machine.fail("ps -eo args | grep -F fake-stdio-secret | grep -v grep")

    # --- Постоянство ключей и возврат после перезапуска.
    before = {n: key(n) for n in ["dsh-online", "localonly-offline"]}
    machine.succeed("systemctl restart llm-gateway-alice.service")
    machine.wait_for_open_port(PORT)
    assert before == {n: key(n) for n in ["dsh-online", "localonly-offline"]}, "ключи не должны меняться"
    code, _ = ask("local-chat", key("dsh-online"))
    assert code == 200

    # --- Остановка убирает публикацию ключей.
    machine.succeed("systemctl stop llm-gateway-alice.service")
    machine.fail(f"test -e {KEYS}/dsh-online")
  '';
}
