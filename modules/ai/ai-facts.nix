# Фича: ai-facts · Слот: — · Домен: ai · Классы: N · Для: всех фич домена ai и хоста
# Контракт: ARCH-4, AI_SUBSYSTEM.md §2.3, §3.6. Объявляет схему my.ai.* (аналог
# host-facts) без значений и без пакетов. keepAlive — без default: явный выбор
# хоста (STR-8 называет его примером значения, задаваемого прямо в hosts/<хост>.nix).
# modelsDir — на томе данных вне снимков и бэкапа (AI-INF-8, STO-1); backup проверяет это
# assertion'ом, читая опцию.
# gateway.providers/cloudRoles/agents/budget (R8.5, R9.16, ADR-45) — без значений:
# заполняет хост (P.1), читает llm-gateway и agents-tools (через osConfig). Цены моделей
# провайдера (`providers.<id>.prices`, R9.26, ADR-49) — тоже факт хоста: по ним шлюз считает бюджеты.
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

        gateway = {
          portBase = lib.mkOption {
            type = lib.types.port;
            default = 11500;
            description = "Базовый порт пользовательских шлюзов; порт = portBase + (uid − 1000) (AI-GW-1).";
          };

          providers = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  type = lib.mkOption {
                    type = lib.types.str;
                    description = "Тип провайдера у реализации шлюза (базовый тип Bifrost, transports/config.schema.json). Только прямые провайдеры (ADR-45).";
                  };
                  nativeModels = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Собственные модели провайдера для сквозного маршрута (AI-ROLE-5): шлюз пропускает их без подмены. Явный перечень, не маска.";
                  };
                  baseUrl = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Адрес API; null — штатный у типа. Нужен тестам (фальшивый провайдер на loopback).";
                  };
                  prices = lib.mkOption {
                    type = lib.types.attrsOf (
                      lib.types.submodule {
                        options = lib.genAttrs [ "input" "cacheRead" "output" ] (
                          n:
                          lib.mkOption {
                            type = lib.types.number;
                            description = "Цена `${n}` (вход без кэша / вход из кэша / выход), USD за 1M токенов.";
                          }
                        );
                      }
                    );
                    default = { };
                    description = ''
                      Модель → цены, по которым шлюз считает расход и бюджеты (AI-GW-6, ADR-49).
                      Тариф — тот, что провайдер реально списывает; справочник цен реализации шлюза
                      не используется. Облачная модель без цены бюджет не расходует — сборка не пройдёт.
                    '';
                  };
                };
              }
            );
            default = { };
            description = ''
              Провайдеры облачных моделей (ADR-45): нейтральный id → тип и перечень
              собственных моделей. Секрет называется по id
              (`ai.gateway.providerKey.<id>`, SEC-3) — имён вендоров в ключах нет.
              Заполняет хост.
            '';
          };

          cloudRoles = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  provider = lib.mkOption {
                    type = lib.types.str;
                    description = "Нейтральный id провайдера из `my.ai.gateway.providers`.";
                  };
                  model = lib.mkOption {
                    type = lib.types.str;
                    description = "Идентификатор модели у провайдера (раздел 4 AI_SUBSYSTEM.md, Приложение P.2).";
                  };
                };
              }
            );
            default = { };
            description = ''
              Облачная роль (cost-autonomous/strong-autonomous/experimental, раздел 4
              AI_SUBSYSTEM.md) → id провайдера и модель. Без значений (STR-8):
              заполняет хост (Приложение P.1).
            '';
          };

          budget = {
            maxUSD = lib.mkOption {
              type = lib.types.nullOr lib.types.numbers.positive;
              default = null;
              description = "Лимит расходов на каждый ключ доступа, имеющий облачные права, USD за период (AI-GW-6, MAY). null — без лимита шлюза: расход контролирует владелец у провайдера (решение 2026-11-14).";
            };
            resetDuration = lib.mkOption {
              type = lib.types.str;
              default = "1M";
              description = "Период сброса лимита (формат Bifrost: 1d, 1w, 1M, …).";
            };
          };

          agents = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  cloudRoles = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Облачные роли, доступные агенту в режиме `online`.";
                  };
                  localRoles = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    description = "Локальные роли агента; ключ режима `offline` допускает только их. Ролей, которых нет в `my.ai.local`, шлюз не публикует.";
                  };
                  nativeProvider = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Для агента, привязанного к семейству моделей (AI-ROLE-5): id провайдера, чьи `nativeModels` он вправе вызывать в режиме `online`.";
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
              `<агент>-online` и `<агент>-offline`. Права запрещены по умолчанию;
              значения задаёт хост.
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
