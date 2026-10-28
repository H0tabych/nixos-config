# Фича: ai-facts · Слот: — · Домен: ai · Классы: N · Для: всех фич домена ai и хоста
# Контракт: ARCH-4, AI_SUBSYSTEM.md §2.3, §3.6. Объявляет схему my.ai.* (аналог
# host-facts) без значений и без пакетов. keepAlive — без default: явный выбор
# хоста (STR-8 называет его примером значения, задаваемого прямо в hosts/<хост>.nix).
# modelsDir — заглушка до отдельного тома storage/layout (AI-INF-8, STO-1).
# gateway.cloudRoles (R8.5) — без значений: заполняет хост (P.1), читает
# llm-gateway через osConfig (HM-класс).
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
            default = "/var/lib/ollama/models";
            description = ''
              Каталог моделей (AI-INF-8). Заглушка до подключения отдельного
              тома вне снимков и бэкапа (storage/layout, STO-1/STO-8).
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

          cloudRoles = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  provider = lib.mkOption {
                    type = lib.types.str;
                    description = "Идентификатор провайдера у реализации шлюза (раздел `providers` конфига Bifrost — profильное имя, не вендор в смысле SEC-3: это техническое имя бэкенда, а не имя секрета).";
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
              AI_SUBSYSTEM.md) → провайдер+модель. Без значений (STR-8): заполняет
              хост (Приложение P.1). У каждой роли свой секрет ключа провайдера
              (secrets/users/<user>.yaml, ключ `ai.gateway.providerKey.<роль>` —
              нейтральное имя по SEC-3, даже если две роли делят один вендорский ключ).
            '';
          };
        };
      };
    };
}
