# Приватная часть: llm-gateway · Владелец: modules/ai/llm-gateway.nix (STR-6)
# Чистая функция: политика хоста → ШАБЛОН config.json шлюза (Bifrost). Секретов в
# шаблоне нет: на их месте метки `@ИМЯ@`, службу (юнит) собирает соседняя приватная часть фичи
# (подстановка при старте из учётных данных и состояния службы, ADR-45, SEC-4).
# Поля и их расположение — по официальной схеме апстрима (transports/config.schema.json,
# тег transports/v2.1.0):
#   - client.enforce_auth_on_inference — ключ на каждом запросе (AI-GW-4);
#   - client.disable_content_logging — содержимое не логируется (AI-GW-7);
#   - providers.<тип> — облачные провайдеры под ВСТРОЕННЫМ именем типа (`deepseek`, …):
#     custom_provider_config не годится — рантайм принимает базовыми только anthropic,
#     bedrock, cohere, gemini, openai, huggingface, replicate (config.go:ValidateCustomProvider,
#     проверено 2026-11-06), а у встроенного типа свои особенности протокола (рассуждение
#     DeepSeek). Нейтральный id (SEC-3) живёт в политике хоста и sops, имя типа — только
#     здесь, во внутренностях конфига; поэтому тип у каждого id уникален (assertion фичи);
#   - providers.local-inference — локальный бэкенд без ключа: custom-провайдер поверх
#     OpenAI-совместимого API (AI-INF-2), замена слота inference-service шлюз не
#     затрагивает (AI-A13, A18);
#   - governance.virtual_keys[] — по ключу на пару «агент × режим» (AI-GW-4):
#     allow_all_providers = false, провайдеры перечислены в provider_configs, инструменты
#     (mcp_configs) пусты — по умолчанию запрещено всё; ключ `offline` получает только
#     локальный провайдер;
#   - governance.budgets[] — лимит расходов на каждый ключ с облачными правами (AI-GW-6);
#   - governance.routing_rules[] — индирекция «роль → провайдер + модель» (AI-GW-2) и
#     сквозной маршрут собственных моделей провайдера (AI-ROLE-5): условие по имени
#     модели, а `model` в цели не задан — берётся из запроса, без подмены.
#
# Почему routing_rules, а не алиасы ключей (разобрано по исходникам 2026-10-29): алиас
# на ключе резолвится только при уже известном провайдере, а имя роли провайдера не
# несёт. CEL-переменная называется `model`.
#
# AI-GW-5 (fallback) — «явная ошибка» (контракт допускает): `fallbacks` правила —
# цепочка провайдеров при той же модели и перевод «облако → локальная роль» не выражает.
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
  cloudRoles, # my.ai.gateway.cloudRoles: роль → { provider, model }
  providers, # my.ai.gateway.providers: id → { type, nativeModels, baseUrl }
  agents, # my.ai.gateway.agents: агент → { cloudRoles, localRoles, nativeProvider }
  budget, # my.ai.gateway.budget: { maxUSD, resetDuration }
  frameworkOverride ? { }, # добавка к корню конфига (тесты без сети: справочники цен)
  proxyUrl ? null, # адрес HTTP-входа туннеля (режим M1, NET-10); null — прокси не нужен
}:
let
  # Имя провайдера локальных ролей — наше, не встроенное в шлюз (AI-A13).
  localProvider = "local-inference";
  modes = [
    "online"
    "offline"
  ];

  keyId = agent: mode: "${agent}-${mode}";

  # Имя провайдера в конфиге шлюза — тип (встроенное имя), по id политики хоста.
  nameOf = id: providers.${id}.type;

  cloudProviders = lib.mapAttrs' (
    id: p:
    lib.nameValuePair (nameOf id) (
      {
        keys = [
          {
            name = id;
            value = "@PROVIDER_${id}@";
            models = [ "*" ];
            weight = 1.0;
          }
        ];
      }
      // lib.optionalAttrs (p.baseUrl != null) { network_config.base_url = p.baseUrl; }
      // lib.optionalAttrs (proxyUrl != null) {
        proxy_config = {
          type = "http";
          url = proxyUrl;
        };
      }
    )
  ) providers;

  mkRoutingRule = priority: id: cel: target: {
    id = "route-${id}";
    name = "route-${id}";
    enabled = true;
    cel_expression = cel;
    targets = [ (target // { weight = 1.0; }) ];
    scope = "global";
    inherit priority;
  };

  celList = models: "[" + lib.concatMapStringsSep ", " (m: "'${m}'") models + "]";

  routingRules = lib.imap0 (i: f: f i) (
    lib.mapAttrsToList (
      role: model: priority:
      mkRoutingRule priority role "model == '${role}'" {
        provider = localProvider;
        inherit model;
      }
    ) localRoles
    ++ lib.mapAttrsToList (
      role: r: priority:
      mkRoutingRule priority role "model == '${role}'" {
        provider = nameOf r.provider;
        inherit (r) model;
      }
    ) cloudRoles
    # Сквозной маршрут (AI-ROLE-5): `model` не задан — идёт как в запросе.
    ++ lib.mapAttrsToList (
      id: p: priority:
      mkRoutingRule priority "native-${id}" "model in ${celList p.nativeModels}" {
        provider = nameOf id;
      }
    ) (lib.filterAttrs (_: p: p.nativeModels != [ ]) providers)
  );

  # Права ключа. Онлайн: облачные роли агента + нативные модели привязанного
  # провайдера + локальные роли; офлайн: только локальные роли (AI-GW-4).
  # allowed_models — реальные модели (проверяется результат маршрутизации; имена
  # ролей в перечень не нужны — подтверждено ВМ-тестом tests/llm-gateway.nix).
  agentCloud =
    agent:
    let
      roles = lib.filter (r: cloudRoles ? ${r}) agent.cloudRoles;
      byProvider = lib.groupBy (r: cloudRoles.${r}.provider) roles;
      native = lib.optionalAttrs (agent.nativeProvider != null) {
        ${agent.nativeProvider} = [ ];
      };
    in
    lib.mapAttrs (
      id: rs:
      lib.unique (
        map (r: cloudRoles.${r}.model) rs
        ++ lib.optionals (agent.nativeProvider == id) providers.${id}.nativeModels
      )
    ) ((lib.mapAttrs (_: _: [ ]) native) // byProvider);

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

  providerConfigs =
    mode: agent:
    agentLocal agent
    ++ lib.optionals (mode == "online") (
      lib.mapAttrsToList (id: models: {
        provider = nameOf id;
        allowed_models = models;
        key_ids = [ "*" ]; # v2: пустой список = ни одного ключа провайдера
        weight = null;
      }) (agentCloud agent)
    );

  virtualKeys = lib.concatLists (
    lib.mapAttrsToList (
      name: agent:
      map (mode: {
        id = keyId name mode;
        name = keyId name mode;
        value = "@KEY_${keyId name mode}@";
        allow_all_providers = false;
        provider_configs = providerConfigs mode agent;
        mcp_configs = [ ]; # инструменты — только по явному разрешению (R9.20)
      }) modes
    ) agents
  );

  budgets = lib.concatLists (
    lib.mapAttrsToList (
      name: agent:
      lib.optional (agentCloud agent != { }) {
        id = "budget-${keyId name "online"}";
        max_limit = budget.maxUSD;
        reset_duration = budget.resetDuration;
        virtual_key_id = keyId name "online";
      }
    ) agents
  );
in
frameworkOverride
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

  providers = cloudProviders // {
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

  governance = {
    # Аутентификация management-API (без неё — известные RCE в старых версиях);
    # учётные данные генерирует служба (ADR-45), в sops их нет.
    auth_config = {
      is_enabled = true;
      admin_username = "@ADMIN_USER@";
      admin_password = "@ADMIN_PASS@";
    };
    virtual_keys = virtualKeys;
    inherit budgets;
    routing_rules = routingRules;
  };
}
