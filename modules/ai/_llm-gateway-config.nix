# Приватная часть: llm-gateway · Владелец: modules/ai/llm-gateway.nix (STR-6)
# Чистая функция: политика хоста → ШАБЛОН config.json шлюза (Bifrost). Секретов в
# шаблоне нет: на их месте метки `@ИМЯ@`, службу (юнит) собирает соседняя приватная часть фичи
# (подстановка при старте из состояния службы, ADR-45, SEC-4).
# Поля и их расположение — по официальной схеме апстрима (transports/config.schema.json,
# тег transports/v2.1.0):
#   - client.enforce_auth_on_inference — ключ на каждом запросе (AI-GW-4);
#   - client.disable_content_logging — содержимое не логируется (AI-GW-7);
#   - providers.local-inference — локальный бэкенд без ключа: custom-провайдер поверх
#     OpenAI-совместимого API (AI-INF-2), замена слота inference-service шлюз не
#     затрагивает (AI-A13, A18). Облачных провайдеров в шлюзе нет (ADR-051): агенты ходят к
#     моделям сами, в родных протоколах;
#   - governance.virtual_keys[] — по ключу на пару «агент × режим» (AI-GW-4):
#     allow_all_providers = false, провайдеры перечислены в provider_configs (только локальный и
#     только для локальных ролей агента), инструменты (mcp_configs) — только серверы агента,
#     `online` (AI-GW-14); ключ `offline` инструментов не получает;
#   - governance.routing_rules[] — индирекция «локальная роль → локальная модель» (AI-GW-2).
#
# Почему routing_rules, а не алиасы ключей (разобрано по исходникам 2026-10-29): алиас
# на ключе резолвится только при уже известном провайдере, а имя роли провайдера не
# несёт. CEL-переменная называется `model`.
#
# Значение virtual key ОБЯЗАНО начинаться с "sk-bf-" (governance.VirtualKeyPrefix,
# plugins/governance/main.go), иначе шлюз молча подменяет его своим; префикс добавляет
# служба при генерации ключа.
# priority правил уникален в пределах scope (иначе шлюз падает на старте); правила
# взаимоисключающие, так что это только номер.
{ lib }:
{
  inference, # { host, port } — my.ai.inference
  localRoles, # my.ai.local: роль → тег локальной модели
  agents, # my.ai.gateway.agents: агент → { localRoles, mcp }
  mcp, # MCP-шлюз: { section, keys } — раздел конфига и права ключей (AI-GW-14)
  frameworkOverride ? { }, # добавка к конфигу, сливается рекурсивно (тесты без сети: параметры моделей)
  pricingUrl ? null, # file:// пустого справочника цен: шлюз не качает его с сайта поставщика (AI-GW-13)
}:
let
  # Имя провайдера локальных ролей — наше, не встроенное в шлюз (AI-A13).
  localProvider = "local-inference";
  modes = [
    "online"
    "offline"
  ];

  keyId = agent: mode: "${agent}-${mode}";

  mkRoutingRule = priority: id: cel: target: {
    id = "route-${id}";
    name = "route-${id}";
    enabled = true;
    cel_expression = cel;
    targets = [ (target // { weight = 1.0; }) ];
    scope = "global";
    inherit priority;
  };

  routingRules = lib.imap0 (i: f: f i) (
    lib.mapAttrsToList (
      role: model: priority:
      mkRoutingRule priority role "model == '${role}'" {
        provider = localProvider;
        inherit model;
      }
    ) localRoles
  );

  # Права ключа: локальные роли агента — в обоих режимах; облака в шлюзе нет (ADR-051).
  # allowed_models — реальные модели (проверяется результат маршрутизации; имена
  # ролей в перечень не нужны — подтверждено ВМ-тестом tests/llm-gateway.nix).
  agentLocal =
    agent:
    let
      roles = lib.filter (r: localRoles ? ${r}) agent.localRoles;
    in
    lib.optional (roles != [ ]) {
      provider = localProvider;
      # Не "*": имя модели без правила маршрута шлюз иначе отдаёт единственному
      # провайдеру ключа как есть (проверено ВМ-тестом) — «тихий» проход на локальный бэкенд.
      allowed_models = map (r: localRoles.${r}) roles;
      key_ids = [ "*" ];
      weight = null;
    };

  providerConfigs = agentLocal;

  virtualKeys = lib.concatLists (
    lib.mapAttrsToList (
      name: agent:
      map (mode: {
        id = keyId name mode;
        name = keyId name mode;
        value = "@KEY_${keyId name mode}@";
        allow_all_providers = false;
        provider_configs = providerConfigs agent;
        mcp_configs = mcp.keys name mode; # инструменты — только разрешённые агенту (AI-GW-14)
      }) modes
    ) agents
  );
in
lib.recursiveUpdate frameworkOverride (
  lib.optionalAttrs (pricingUrl != null) { framework.pricing.pricing_url = pricingUrl; }
  // {
    "$schema" = "https://www.getbifrost.ai/schema";
    # По умолчанию ("split") config.json только домешивается к sqlite-базе в состоянии;
    # здесь единственный источник правды — Nix/sops, поэтому присутствующие секции
    # авторитетны при каждом старте.
    source_of_truth = "config.json";

    client = {
      enforce_auth_on_inference = true;
      disable_content_logging = true;
    };

    providers = {
      # Без /v1 в base_url (путь дописывает базовый провайдер openai); is_key_less —
      # ключи не нужны. ПРОВЕРЕНО живым запросом 2026-11-05 (AI-A13).
      ${localProvider} = {
        network_config.base_url = "http://${inference.host}:${toString inference.port}";
        custom_provider_config = {
          base_provider_type = "openai";
          is_key_less = true;
          # Только то, что обещает AI-INF-2; остальное — явный отказ шлюза, а не 404 бэкенда.
          allowed_requests = {
            list_models = true;
            text_completion = true;
            text_completion_stream = true;
            chat_completion = true;
            chat_completion_stream = true;
            embedding = true;
          };
        };
      };
    };

    mcp = mcp.section;

    governance = {
      # Аутентификация management-API (без неё — известные RCE в старых версиях);
      # учётные данные генерирует служба (ADR-45), в sops их нет.
      auth_config = {
        is_enabled = true;
        admin_username = "@ADMIN_USER@";
        admin_password = "@ADMIN_PASS@";
      };
      virtual_keys = virtualKeys;
      # Раздел есть всегда, пустой: снимает лимиты, оставшиеся в базе от прежних версий.
      budgets = [ ];
      routing_rules = routingRules;
    };
  }
)
