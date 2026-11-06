# Фича: ai-facts · Слот: — · Домен: ai · Классы: N · Для: всех фич домена ai и хоста
# Контракт: ARCH-4, AI_SUBSYSTEM.md §2.3, §3.6. Объявляет схему my.ai.* (аналог
# host-facts) без значений и без пакетов. keepAlive — без default: явный выбор
# хоста (STR-8 называет его примером значения, задаваемого прямо в hosts/<хост>.nix).
# modelsDir — на томе данных вне снимков и бэкапа (AI-INF-8, STO-1); backup проверяет это
# assertion'ом, читая опцию.
# gateway.providers/cloudRoles/agents/budget (R8.5, R9.16, ADR-45) — без значений:
# заполняет хост (P.1), читает llm-gateway и agents-tools (через osConfig).
# Зависимости: —
_: {
  flake.modules.nixos.ai-facts =
    { lib, ... }:
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
              description = "Лимит расходов на каждый ключ доступа, имеющий облачные права, USD за период (AI-GW-6). null допустим только без облачных ролей — иначе сборка не пройдёт.";
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
        };
      };
    };
}
