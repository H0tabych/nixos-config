# Фича: ai-facts · Слот: — · Домен: ai · Классы: N · Для: всех фич домена ai и хоста
# Контракт: ARCH-4, AI_SUBSYSTEM.md §2.3, §3.6. Объявляет схему my.ai.* (аналог
# host-facts) без значений и без пакетов. keepAlive — без default: явный выбор
# хоста (STR-8 называет его примером значения, задаваемого прямо в hosts/<хост>.nix).
# modelsDir — заглушка до отдельного тома storage/layout (AI-INF-8, STO-1).
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

        gateway.portBase = lib.mkOption {
          type = lib.types.port;
          default = 11500;
          description = "Базовый порт пользовательских шлюзов (AI-GW-1); не используется до R8.5.";
        };
      };
    };
}
