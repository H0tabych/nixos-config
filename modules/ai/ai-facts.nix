# Фича: ai-facts · Слот: — · Домен: ai · Классы: N · Для: всех фич домена ai и хоста
# Контракт: ARCH-4, AI_SUBSYSTEM.md §2.3, §3.6. Объявляет схему my.ai.* (аналог
# host-facts) без значений и без пакетов. keepAlive — без default: явный выбор
# хоста (STR-8 называет его примером значения, задаваемого прямо в hosts/<хост>.nix).
# modelsDir — на томе данных вне снимков и бэкапа (AI-INF-8, STO-1); backup проверяет это
# assertion'ом, читая опцию.
# gateway.agents/mcp (ADR-45) — без значений: заполняет хост, читает llm-gateway и agents-tools
# (через osConfig). Облачных провайдеров, ролей и бюджетов в шлюзе нет (ADR-051): агенты ходят
# к моделям сами; ключ провайдера для агента — `agentKeys` (фича agents-keys).
# Зависимости: —
_: {
  flake.modules.nixos.ai-facts =
    { lib, ... }:
    let
      opt =
        type: default: description:
        lib.mkOption { inherit type default description; };
    in
    {
      options.my.ai = {
        inference = {
          host = lib.mkOption {
            type = lib.types.str;
            default = "127.0.0.1";
            description = "Loopback-адрес инференса (AI-INF-1, NET-4).";
          };
          port = lib.mkOption {
            type = lib.types.port;
            default = 11434;
            description = "Порт инференс-сервиса.";
          };
          keepAlive = lib.mkOption {
            type = lib.types.str;
            description = "Время жизни загруженной модели в простое (AI-RES-2) — факт хоста.";
          };
          modelsDir = lib.mkOption {
            type = lib.types.str;
            default = "/var/lib/nosnapshot/models";
            description = ''
              Каталог моделей (AI-INF-8): подкаталог тома данных вне снимков и бэкапа
              (storage/layout, STO-1/STO-8). Без имени реализации инференса. Переопределять
              можно только каталогом на томе, который backup не снимает: иначе сборка
              не пройдёт.
            '';
          };
        };

        local = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Роль → локальная модель. Вычисляется фичей inference-service, читает llm-gateway.";
        };

        search = {
          host = lib.mkOption {
            type = lib.types.str;
            default = "127.0.0.1";
            description = "Loopback-адрес службы поиска в сети (слот web-search, NET-4).";
          };
          port = lib.mkOption {
            type = lib.types.port;
            default = 8888;
            description = "Порт службы поиска.";
          };
        };

        agentKeys = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options.sopsKey = lib.mkOption {
                type = lib.types.str;
                description = "Ключ секрета в sops пользователя (`secrets/users/<user>.yaml`), содержащий ключ провайдера.";
              };
            }
          );
          default = { };
          description = "Агенты, ходящие к провайдеру напрямую (ADR-051): агент → секрет с ключом провайдера; читает agents-keys. Заполняет хост.";
        };

        gateway = {
          portBase = lib.mkOption {
            type = lib.types.port;
            default = 11500;
            description = "Базовый порт пользовательских шлюзов; порт = portBase + (uid − 1000) (AI-GW-1).";
          };

          agents = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  localRoles = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Локальные роли агента; ключ режима `offline` допускает только их. Ролей, которых нет в `my.ai.local`, шлюз не публикует.";
                  };
                  mcp = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Серверы MCP-шлюза (`my.ai.gateway.mcp`), инструменты которых доступны ключу `online` (AI-GW-14). Ключ `offline` инструментов не получает.";
                  };
                };
              }
            );
            default = { };
            description = ''
              Состав матрицы ключей доступа (AI-GW-4): на каждого агента — два ключа,
              `<агент>-online` и `<агент>-offline`. Права запрещены по умолчанию (локальные
              роли и инструменты MCP-шлюза); значения задаёт хост.
            '';
          };

          mcp = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  type = lib.mkOption {
                    type = lib.types.enum [
                      "stdio"
                      "http"
                    ];
                    description = "`stdio` — шлюз запускает команду под своей учётной записью; `http` — удалённый сервер.";
                  };
                  command =
                    opt (lib.types.nullOr lib.types.str) null
                      "stdio: путь к исполняемому файлу (из пакета, без загрузок из сети, AI-CTX-5).";
                  args = opt (lib.types.listOf lib.types.str) [ ] "stdio: аргументы команды.";
                  env = opt (lib.types.attrsOf lib.types.str) { } "stdio: несекретные переменные окружения сервера.";
                  url = opt (lib.types.nullOr lib.types.str) null "http: адрес сервера.";
                  headers = opt (lib.types.attrsOf lib.types.str) { } "http: несекретные заголовки запроса.";
                  secret =
                    opt lib.types.bool false
                      "Серверу нужен секрет `ai.gateway.mcpToken.<id>` (SEC-3). Нет значения — сервер вычёркивается, юнит не падает (AI-GW-9).";
                  secretHomeFile =
                    opt (lib.types.nullOr lib.types.str) null
                      "Путь от домашнего каталога пользователя: секрет — из этого файла вместо sops (читает root; файл виден агенту с доступом к $HOME). Нет файла — сервер вычёркивается.";
                  secretEnv =
                    opt (lib.types.nullOr lib.types.str) null
                      "stdio: имя переменной окружения, в которую обёртка кладёт секрет.";
                  secretHeader = opt lib.types.str "Authorization" "http: заголовок, несущий секрет.";
                  secretPrefix = opt lib.types.str "Bearer " "http: префикс значения заголовка с секретом.";
                };
              }
            );
            default = { };
            description = ''
              MCP-шлюз (AI-GW-14): нейтральный id → сервер, которому нужен секрет или который
              удалённый. Серверы без секретов запускает сам агент в песочнице (список в dotfiles,
              AI-CTX-3/4). Секрет называется по id (`ai.gateway.mcpToken.<id>`). Заполняет хост
              и фичи-реализации (web-search, mcp-jira).
            '';
          };
        };
      };
    };
}
