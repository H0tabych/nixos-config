# Приватная часть: llm-gateway · Владелец: modules/ai/llm-gateway.nix (STR-6)
# Чистая функция: attrset → config.json шлюза (Bifrost). Поля и их расположение
# взяты из официальной JSON Schema апстрима (transports/config.schema.json,
# тег transports/v2.1.0) и официальных примеров (examples/configs/withroutingrules):
#   - client.enforce_auth_on_inference — требует ключ на каждом инференс-запросе (AI-GW-4);
#   - client.disable_content_logging — содержимое не логируется по умолчанию (AI-GW-7);
#   - providers.ollama.keys[].ollama_key_config.url — локальный бэкенд без ключа (value="");
#   - governance.auth_config.is_enabled — аутентификация management-API (без неё —
#     известные RCE через management-интерфейс в более старых версиях; в апстриме
#     выключена по умолчанию, пин версии и включение этого поля — обязательны);
#   - governance.virtual_keys[] — единый ключ доступа (AI-GW-3/4; "ключ доступа" в контракте
#     единственное число, поэтому один virtual key с allow_all_providers, не по ключу на роль);
#   - governance.routing_rules[] — ИНДИРЕКЦИЯ «роль → провайдер + модель» (AI-GW-2).
#
# Почему routing_rules, а не providers.*.keys[].aliases (разобрано по исходникам
# 2026-10-29, после живого отказа "could not auto resolve a provider"): алиасы на
# ключе резолвятся функцией ResolveAlias(provider, model) — она требует УЖЕ
# известного провайдера, то есть отображает имя модели только после того, как
# провайдер выбран. Имя роли провайдера не несёт, поэтому выбрать его было неоткуда.
# Каноничная альтернатива — писать "openrouter/<роль>" в запросе — протащила бы имя
# провайдера в dotfiles, что запрещено (AI-ROLE-2, DOT-1/DOT-6). routing_rules
# решает ровно это: CEL-условие по имени модели + целевой провайдер и реальная
# модель, всё задаётся Nix. Переменная CEL называется `model` (не request.model) —
# по примерам апстрима.
#
# AI-GW-5 (fallback) здесь реализован как «явная ошибка», что контракт допускает
# прямо («запрос получает явную ошибку ЛИБО переводится на локальную роль»).
# Поле routing_rules[].fallbacks — цепочка ПРОВАЙДЕРОВ при неизменной модели,
# поэтому «облако → локальная модель» им не выражается: ollama получил бы
# облачное имя модели и всё равно отказал. Перевод на локальную роль — отдельная
# задача (ПРОВЕРИТЬ при R8.6, когда появится реальный потребитель-агент).
#
# Значения секретов — напрямую, не через "env.<ИМЯ>". Ссылки "env." шлюз
# поддерживает (schemas.SecretVar), но тогда секрет живёт в двух артефактах
# (config.json + EnvironmentFile) вместо одного, а выигрыша нет: сам config.json
# всё равно секрет (sops.templates, 0400, не в /nix/store, SEC-4) — тот же класс,
# что tunnel-xray.json у tunnel-xray.nix.
# ВАЖНО (корень первого сбоя, по исходникам transports/bifrost-http/lib/config.go:3106):
# значение virtual key ОБЯЗАНО начинаться с "sk-bf-" (governance.VirtualKeyPrefix).
# Иначе синхронизация config.json молча отбрасывает заданное значение и генерирует
# своё ("We are generating a new one for you"), после чего любой запрос с нашим
# ключом получает access_not_found. Префикс добавляет Nix (см. вызывающую сторону),
# а не человек в sops: забыть его — значит получить тихую подмену ключа, которую
# видно только в sqlite-базе шлюза.
{ lib }:
{
  inference, # { host, port } — my.ai.inference
  localRoles, # my.ai.local: роль → тег локальной модели
  cloudRoles, # my.ai.gateway.cloudRoles: роль → { provider, model }
  roleKeyValue, # роль (атрибут cloudRoles) → значение секрета этой роли
  accessKeyValue,
  adminUserValue,
  adminPassValue,
}:
let
  cloudKeysByProvider = lib.foldlAttrs (
    acc: role: r:
    acc
    // {
      ${r.provider} = (acc.${r.provider} or [ ]) ++ [
        {
          name = role;
          value = roleKeyValue role;
          models = [ "*" ];
          weight = 1.0;
        }
      ];
    }
  ) { } cloudRoles;

  # proxy_config.type = "environment" — ОБЯЗАТЕЛЕН для облачных провайдеров
  # (разобрано 2026-10-29 живой проверкой + исходниками core/providers/utils/utils.go:705):
  # Bifrost ходит к провайдерам через fasthttp, а тот, в отличие от net/http,
  # переменные http_proxy/https_proxy сам НЕ читает. Без этого поля запрос уходил
  # напрямую, минуя туннель, и OpenRouter отвечал 403 "Access denied by security
  # policy" (прямой путь заблокирован), тогда как через туннель тот же запрос
  # проходит. "environment" включает fasthttpproxy.FasthttpProxyHTTPDialer(),
  # который берёт адрес из окружения юнита — поэтому адрес прокси здесь НЕ
  # дублируется (NET-10, L-7): он приходит из единственного места, сессии.
  # Для ollama поле не ставится: это loopback, прокси ему не нужен (и no_proxy
  # его и так исключает).
  cloudProviders = lib.mapAttrs (_: keys: {
    inherit keys;
    proxy_config.type = "environment";
  }) cloudKeysByProvider;

  # Одно правило на роль: имя роли на входе → реальный провайдер и модель.
  # priority ОБЯЗАН быть уникальным в пределах scope: иначе шлюз падает на старте
  # с "routing rule with priority N already exists for scope 'global'" (проверено
  # живым запуском 2026-10-29; ограничение рантайма/БД, в JSON Schema его нет).
  # Правила взаимоисключающие (условие — равенство имени роли), поэтому порядок
  # значения не имеет: priority здесь только уникальный номер, не приоритет по смыслу.
  mkRoutingRule = priority: role: provider: model: {
    id = "role-${role}";
    name = "role-${role}";
    enabled = true;
    cel_expression = "model == '${role}'";
    targets = [
      {
        inherit provider model;
        weight = 1.0;
      }
    ];
    scope = "global";
    inherit priority;
  };

  routingRules = lib.imap0 (i: f: f i) (
    lib.mapAttrsToList (
      role: model: priority:
      mkRoutingRule priority role "ollama" model
    ) localRoles
    ++ lib.mapAttrsToList (
      role: r: priority:
      mkRoutingRule priority role r.provider r.model
    ) cloudRoles
  );
in
{
  "$schema" = "https://www.getbifrost.ai/schema";
  # По умолчанию ("split") Bifrost только домешивает config.json к своей
  # sqlite-базе в StateDirectory, не перезаписывая существующие записи —
  # несовместимо с тем, что здесь единственный источник правды — Nix/sops,
  # а не состояние, накопленное рантаймом. "config.json" делает присутствующие
  # секции (включая virtual_keys) авторитетными при каждом старте.
  source_of_truth = "config.json";

  client = {
    enforce_auth_on_inference = true;
    disable_content_logging = true;
  };

  providers = cloudProviders // {
    ollama = {
      keys = [
        {
          name = "ollama-local";
          value = "";
          models = [ "*" ];
          weight = 1.0;
          ollama_key_config.url = "http://${inference.host}:${toString inference.port}";
        }
      ];
    };
  };

  governance = {
    auth_config = {
      is_enabled = true;
      admin_username = adminUserValue;
      admin_password = adminPassValue;
    };
    virtual_keys = [
      {
        id = "access";
        name = "access";
        value = accessKeyValue;
        allow_all_providers = true;
      }
    ];
    routing_rules = routingRules;
  };
}
