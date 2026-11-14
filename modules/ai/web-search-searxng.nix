# Фича: web-search-searxng · Слот: web-search · Домен: ai · Классы: N · Для: хоста с ml
# Контракт: AI-CTX-4 (поиск в сети — сервис хоста за нейтральной командой `web-search-mcp` как
# инструмент MCP-шлюза), AI_SUBSYSTEM.md §3 (слот `web-search`, P.1), SLOT-1…3, NET-4.
# SearXNG слушает ТОЛЬКО loopback (`my.ai.search.{host,port}`); формат JSON включён — по нему
# отвечает MCP-сервер. Встроенный поиск агентов, отправляющий запросы стороннему провайдеру,
# выключен (AI-CTX-4).
#
# Класс N, а не N+H (как в первой редакции таблицы §3): команду запускает шлюз — системная
# служба с DynamicUser, пользовательского PATH у неё нет. Поэтому обёртка собирается здесь и
# регистрируется как stdio-сервер шлюза (`my.ai.gateway.mcp.web-search`, AI-GW-14); ключам
# агентов её разрешает хост (`my.ai.gateway.agents.<агент>.mcp`). Пакет `mcp-searxng` — из unstable (в 26.05 нет, ПРОВЕРЕНО `nix eval`, ARCH-14);
# адрес службы он берёт из SEARXNG_INSTANCE_URL (ПРОВЕРЕНО по исходникам пакета).
# Секрет службы (`server.secret_key`) — не секрет хоста: его генерирует при первом запуске
# отдельный юнит в файл root 0400, а `environmentFile` подставляет в настройки (в sops его нет).
# Зависимости: ai-facts (my.ai.search.*, my.ai.gateway.mcp) — схема my.*, состав — пресетом ml (ARCH-3).
_: {
  flake.modules.nixos.web-search-searxng =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      search = config.my.ai.search;
      secretDir = "/var/lib/searx-secret";
      secretFile = "${secretDir}/env";
      mcp = pkgs.writeShellApplication {
        name = "web-search-mcp";
        text = ''
          export SEARXNG_INSTANCE_URL="http://${search.host}:${toString search.port}"
          exec ${lib.getExe pkgs.unstable.mcp-searxng} "$@"
        '';
      };
    in
    {
      my.ai.gateway.mcp.web-search = {
        type = "stdio";
        command = lib.getExe mcp;
      };

      services.searx = {
        enable = true;
        environmentFile = secretFile;
        settings = {
          use_default_settings = true;
          server = {
            bind_address = search.host;
            inherit (search) port;
            secret_key = "$SEARX_SECRET_KEY";
            limiter = false; # единственный клиент — шлюз на loopback; лимитер требует Redis
            public_instance = false;
            image_proxy = false;
          };
          search.formats = [
            "html"
            "json"
          ];
        };
      };

      systemd.services.searx-secret = {
        description = "Секрет службы поиска (создаётся один раз)";
        # EnvironmentFile читает searx-init (он готовит settings.yml), а не сам searx.
        before = [ "searx-init.service" ];
        requiredBy = [ "searx-init.service" ];
        path = [ pkgs.coreutils ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
        };
        script = ''
          mkdir -p ${secretDir}
          [ -s ${secretFile} ] || printf 'SEARX_SECRET_KEY=%s\n' \
            "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')" > ${secretFile}
        '';
      };
    };
}
