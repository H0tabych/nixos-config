# Проверка свойства (STRUCTURE 5.1): слот `web-search` (AI-CTX-4, R9.23) — SearXNG слушает
# только loopback, отвечает JSON (по нему работает MCP-сервер), секрет службы создан юнитом
# и недоступен пользователю, а команда `web-search-mcp` из политики шлюза — настоящий
# MCP-сервер по stdio. Выход в интернет в ВМ нет: поисковые движки недоступны, поэтому
# проверяется ответ службы, а не выдача.
{
  pkgs,
  nixosModules,
  ...
}:
let
  n = nixosModules;
in
pkgs.testers.runNixOSTest {
  name = "web-search";

  # Нужен overlay из nix-settings (pkgs.unstable: mcp-searxng), как на настоящем хосте.
  node.pkgsReadOnly = false;

  nodes.machine =
    { config, ... }:
    {
      imports = [
        n.host-facts
        n.nix-settings
        n.ai-facts
        n.web-search-searxng
      ];

      my.host = {
        name = "web-search-fixture";
        class = "vm";
        stateVersion = "26.05";
        users = [ ];
      };

      environment.systemPackages = [
        pkgs.curl
        pkgs.jq
      ];
      # Путь команды из политики шлюза — туда, где его ждёт тест.
      environment.etc."web-search-mcp-command".text = config.my.ai.gateway.mcp.web-search.command;
      users.users.alice = {
        isNormalUser = true;
        uid = 2001;
      };
    };

  testScript = ''
    import json

    machine.wait_for_unit("searx.service")
    machine.wait_for_open_port(8888)

    # Слушает только loopback (NET-4): ни 0.0.0.0, ни внешнего адреса.
    listen = machine.succeed("ss -ltnH 'sport = :8888' | awk '{print $4}'").split()
    assert listen == ["127.0.0.1:8888"], f"SearXNG слушает не только loopback: {listen}"

    # JSON-API отвечает (формат включён) — разбираемый JSON с полем results, хотя движки недоступны.
    out = machine.succeed("curl -s -m 60 'http://127.0.0.1:8888/search?q=test&format=json'")
    assert "results" in json.loads(out), out[:200]

    # Секрет службы: создан юнитом, root 0400, пользователю недоступен.
    machine.succeed("test -s /var/lib/searx-secret/env")
    assert machine.succeed("stat -c %a /var/lib/searx-secret/env").strip() == "600"
    machine.fail("su alice -c 'cat /var/lib/searx-secret/env'")

    # web-search-mcp — настоящий MCP-сервер по stdio.
    cmd = machine.succeed("cat /etc/web-search-mcp-command").strip()
    req = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "t", "version": "0"}}})
    lst = json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
    ready = json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"})
    out = machine.succeed(f"(echo '{req}'; echo '{ready}'; echo '{lst}'; sleep 3) | {cmd} 2>/dev/null")
    replies = [json.loads(l) for l in out.splitlines() if l.startswith("{")]
    tools = [t["name"] for r in replies for t in r.get("result", {}).get("tools", [])]
    assert tools, f"web-search-mcp не отдал инструменты: {out[:300]}"
    print("web-search-mcp, инструменты:", tools)
  '';
}
