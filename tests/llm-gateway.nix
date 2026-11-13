# Проверка свойства (STRUCTURE 5.1): шлюз v2 (ADR-45, R9.16) — AI-A14, AI-A6 (права),
# матрица ключей «агент × режим» (AI-GW-4), сквозной маршрут (AI-ROLE-5), роли (AI-GW-2).
# Конфиг шлюза не показывает, что делает настоящий бинарник Bifrost с правами ключей, поэтому
# тест запускает ТОТ ЖЕ юнит (`modules/ai/_llm-gateway-service.nix`) и ТОТ ЖЕ шаблон
# (`_llm-gateway-config.nix`), что и хост, с реальным бинарником, а вместо облачного
# провайдера и локального инференса — фальшивый HTTP-сервер на loopback (запросы пишутся в
# журнал: видно, куда дошёл запрос, под какой моделью и с каким ключом провайдера).
# Секрет провайдера — обычный файл root 0400 вместо sops; второй провайдер с ПУСТЫМ секретом
# проверяет AI-A14 (юнит не `failed` без облачных ключей).
{
  pkgs,
  lib,
  ...
}:
let
  buildConfig = import ../modules/ai/_llm-gateway-config.nix { inherit lib; };
  pkg = pkgs.callPackage ../modules/ai/_llm-gateway-package.nix { };

  providers = {
    primary = {
      type = "deepseek";
      baseUrl = "http://127.0.0.1:9000";
      nativeModels = [
        "native-big"
        "native-small"
      ];
    };
    spare = {
      type = "openai";
      baseUrl = "http://127.0.0.1:9000";
      nativeModels = [ ];
    };
  };
  cloudRoles = {
    cost-autonomous = {
      provider = "primary";
      model = "model-cheap";
    };
    experimental = {
      provider = "spare";
      model = "model-spare";
    };
  };
  agents = {
    dsh = {
      cloudRoles = [
        "cost-autonomous"
        "experimental"
      ];
      localRoles = [ "local-chat" ];
      nativeProvider = "primary";
    };
    localonly = {
      cloudRoles = [ ];
      localRoles = [ "local-chat" ];
      nativeProvider = null;
    };
  };
  template = buildConfig {
    inherit providers cloudRoles agents;
    budget = {
      maxUSD = 10;
      resetDuration = "1M";
    };
    inference = {
      host = "127.0.0.1";
      port = 9001;
    };
    localRoles.local-chat = "local-model";
    # ВМ без сети: справочники цен и параметров моделей берутся из пустых файлов
    # (иначе шлюз падает при первом старте — загрузка с getbifrost.ai).
    frameworkOverride.framework.pricing = {
      pricing_url = "file://${pkgs.writeText "pricing.json" "{}"}";
      model_parameters_url = "file://${pkgs.writeText "model-params.json" "{}"}";
    };
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
    inherit providers;
    keyIds = [
      "dsh-online"
      "dsh-offline"
      "localonly-online"
      "localonly-offline"
    ];
    credPath = id: "/etc/test-secrets/provider-${id}";
  };

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


    for p in (9000, 9001):
        threading.Thread(
            target=ThreadingHTTPServer(("127.0.0.1", p), make(p)).serve_forever, daemon=True
        ).start()
    threading.Event().wait()
  '';
in
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
      "test-secrets/provider-primary" = {
        text = "fake-provider-key\n";
        mode = "0400";
      };
      # Пустой секрет — AI-A14: служба обязана стартовать, роль — отказывать явно.
      "test-secrets/provider-spare" = {
        text = "";
        mode = "0400";
      };
    };

    systemd.services.fake-provider = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = fakeProvider;
    };

    systemd.services.llm-gateway-alice = service // {
      after = service.after ++ [ "fake-provider.service" ];
    };
  };

  testScript = ''
    import json
    import shlex

    PORT = 11501
    LOG = "/var/log/fake-provider.jsonl"
    KEYS = "/run/llm-gateway/alice"

    machine.wait_for_unit("fake-provider.service")
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


    # --- AI-A14: служба жива при пустом секрете одного из провайдеров.
    machine.succeed("systemctl is-active llm-gateway-alice.service")

    # --- Ключи: файлы пользователя, права, постоянство.
    for name in ["dsh-online", "dsh-offline", "localonly-online", "localonly-offline"]:
        assert key(name).startswith("sk-bf-"), name
    assert len({key(n) for n in ["dsh-online", "dsh-offline", "localonly-online", "localonly-offline"]}) == 4

    # --- Роль → провайдер и реальная модель (AI-GW-2); ключ провайдера — из секрета службы.
    code, body = ask("cost-autonomous", key("dsh-online"))
    assert code == 200, (code, body)
    last = provider_log()[-1]
    assert (last["port"], last["model"]) == (9000, "model-cheap"), last
    assert last["auth"] == "Bearer fake-provider-key", last

    # --- Сквозной маршрут (AI-ROLE-5): модель не подменяется.
    for native in ["native-big", "native-small"]:
        code, body = ask(native, key("dsh-online"))
        assert code == 200, (native, code, body)
        last = provider_log()[-1]
        assert (last["port"], last["model"]) == (9000, native), last

    # --- AI-A17 (часть, видимая шлюзу): клиент dsh говорит по Messages (`/anthropic/v1/messages`,
    # ключ в `x-api-key`) и ходит по собственной модели провайдера; рассуждение и инструменты
    # должны дойти до провайдера, модель — не подмениться.
    def ask_messages(model, token, extra):
        body = {"model": model, "max_tokens": 64, "messages": [{"role": "user", "content": "hi"}]}
        body.update(extra)
        out = machine.succeed(
            f"curl -s -m 20 -o /tmp/out -w '%{{http_code}}' -H 'x-api-key: {token}' "
            f"-H 'anthropic-version: 2023-06-01' -H 'Content-Type: application/json' "
            f"-d {shlex.quote(json.dumps(body))} http://127.0.0.1:{PORT}/anthropic/v1/messages; echo; cat /tmp/out"
        )
        code, _, rest = out.partition("\n")
        return int(code), rest

    tools = [{
        "name": "read_file", "description": "read",
        "input_schema": {"type": "object", "properties": {"path": {"type": "string"}}},
    }]
    code, body = ask_messages(
        "native-big", key("dsh-online"),
        {"thinking": {"type": "enabled", "budget_tokens": 1024}, "tools": tools},
    )
    assert code == 200, f"Messages-маршрут dsh: {code} {body}"
    last = provider_log()[-1]
    assert (last["port"], last["model"]) == (9000, "native-big"), last
    assert last["tools"] == ["read_file"], f"AI-A17: инструменты не дошли до провайдера: {last}"
    print("AI-A17 (Messages → провайдер): поля запроса у провайдера:", last["keys"], last["body"].get("thinking"))
    assert any(k in last["keys"] for k in ("thinking", "reasoning_effort", "reasoning")), (
        f"AI-A17: режим рассуждения потерян при преобразовании шлюзом: {last['keys']}"
    )
    # Ключ режима offline и здесь не даёт облако; ключ чужого агента — тоже.
    before = len(provider_log())
    code, _ = ask_messages("native-big", key("dsh-offline"), {})
    assert code != 200 and len(provider_log()) == before, "offline-ключ на Messages-маршруте"

    # --- Локальная роль доступна обоим режимам.
    for name in ["dsh-online", "dsh-offline", "localonly-online", "localonly-offline"]:
        code, body = ask("local-chat", key(name))
        assert code == 200, (name, code, body)
        last = provider_log()[-1]
        assert (last["port"], last["model"]) == (9001, "local-model"), last

    # --- Матрица запретов (AI-GW-4): до провайдера запрос не доходит.
    denied("cost-autonomous", key("dsh-offline"), "offline-ключ и облачная роль")
    denied("native-big", key("dsh-offline"), "offline-ключ и нативная модель")
    denied("cost-autonomous", key("localonly-online"), "роль не из перечня агента")
    denied("native-big", key("localonly-online"), "нативная модель без привязки к провайдеру")
    denied("native-big", key("localonly-offline"), "offline-ключ localonly и нативная модель")
    denied("experimental", key("dsh-online"), "роль провайдера без ключа (AI-GW-5, AI-GW-9)")
    denied("native-big", None, "запрос без ключа")
    denied("native-big", "sk-bf-wrong", "чужой ключ")
    denied("unknown-model", key("dsh-online"), "модель вне перечней")

    # --- Управляющий API без учётных данных закрыт.
    code = machine.succeed(
        f"curl -s -o /dev/null -w '%{{http_code}}' http://127.0.0.1:{PORT}/api/providers"
    ).strip()
    assert code in ("401", "403"), f"management-API без входа: {code}"

    # --- AI-A6 (права): секреты провайдера и состояние службы недоступны пользователю.
    machine.succeed(f"su alice -c 'cat {KEYS}/dsh-online'")
    machine.fail("su alice -c 'cat /etc/test-secrets/provider-primary'")
    machine.fail("su alice -c 'ls /var/lib/private/llm-gateway-alice'")
    machine.fail("su alice -c 'ls /var/lib/llm-gateway-alice'")
    assert machine.succeed(f"ls {KEYS}").split() == sorted(
        ["dsh-online", "dsh-offline", "localonly-online", "localonly-offline"]
    ), "пользователю публикуются только ключи доступа"
    machine.fail(f"grep -r fake-provider-key {KEYS}")
    # Другой пользователь (без ml, USER-7) не читает чужие ключи и каталог.
    machine.fail(f"su bob -c 'cat {KEYS}/dsh-online'")
    machine.fail(f"su bob -c 'ls {KEYS}'")
    # Учётные данные управляющего API не публикуются пользователю.
    machine.fail(f"test -e {KEYS}/admin-pass")

    # --- Права ключа в самом конфиге (root видит): инструменты пусты, бюджет есть (AI-GW-6, ADR-45).
    cfg = json.loads(machine.succeed("cat /var/lib/private/llm-gateway-alice/config.json"))
    vks = {v["id"]: v for v in cfg["governance"]["virtual_keys"]}
    assert all(v["mcp_configs"] == [] and not v["allow_all_providers"] for v in vks.values())
    assert "spare" not in cfg["providers"], "провайдер без ключа должен быть вычеркнут"
    budgets = {b["virtual_key_id"]: b for b in cfg["governance"]["budgets"]}
    assert budgets["dsh-online"]["max_limit"] == 10 and "localonly-online" not in budgets, budgets

    # --- Постоянство ключей и возврат после перезапуска.
    before = {n: key(n) for n in ["dsh-online", "localonly-offline"]}
    machine.succeed("systemctl restart llm-gateway-alice.service")
    machine.wait_for_open_port(PORT)
    assert before == {n: key(n) for n in ["dsh-online", "localonly-offline"]}, "ключи не должны меняться"
    code, _ = ask("native-small", key("dsh-online"))
    assert code == 200

    # --- Остановка убирает публикацию ключей.
    machine.succeed("systemctl stop llm-gateway-alice.service")
    machine.fail(f"test -e {KEYS}/dsh-online")
  '';
}
