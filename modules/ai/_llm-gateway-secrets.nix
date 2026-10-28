# Приватная часть: llm-gateway · Владелец: modules/ai/llm-gateway.nix (STR-6)
# N-класс целиком: секреты и их рендер в config.json — на каждого пользователя
# с capability ml. Выделено отдельно, чтобы главный файл фичи оставался в
# пределах предупреждения STR-6 (≲150 строк). Один рендер (config.json), не
# два: отдельный env-файл убран 2026-10-29 — Bifrost не раскрывает "env."-ссылки
# в governance.virtual_keys[].value, поэтому значения кладутся в config.json
# прямо (детали — у владельца фичи).
{
  lib,
  secretsFile,
  buildConfig,
  mlUsers,
  gw,
  localRoles,
  inference,
}:
let
  secretsForUser =
    user:
    {
      "ai.gateway.accessKey.${user}" = {
        key = "ai.gateway.accessKey";
        sopsFile = secretsFile "users/${user}.yaml";
        owner = user;
        mode = "0400";
      };
      "ai.gateway.admin.user.${user}" = {
        key = "ai.gateway.admin.user";
        sopsFile = secretsFile "users/${user}.yaml";
        owner = user;
        mode = "0400";
      };
      "ai.gateway.admin.pass.${user}" = {
        key = "ai.gateway.admin.pass";
        sopsFile = secretsFile "users/${user}.yaml";
        owner = user;
        mode = "0400";
      };
    }
    // lib.mapAttrs' (
      role: _:
      lib.nameValuePair "ai.gateway.providerKey.${role}.${user}" {
        key = "ai.gateway.providerKey.${role}";
        sopsFile = secretsFile "users/${user}.yaml";
        owner = user;
        mode = "0400";
      }
    ) gw.cloudRoles;

  # Префикс обязателен: без него шлюз подменяет ключ своим (обоснование — в
  # шапке файла-построителя конфига). Добавляется здесь, а не в sops, чтобы один
  # и тот же вывод шёл и в config.json, и в файл для клиентов — разойтись не могут.
  accessKeyFor = placeholder: user: "sk-bf-" + placeholder "ai.gateway.accessKey.${user}";

  configJsonFor =
    placeholder: user:
    buildConfig {
      inherit inference localRoles;
      inherit (gw) cloudRoles;
      roleKeyValue = role: placeholder "ai.gateway.providerKey.${role}.${user}";
      accessKeyValue = accessKeyFor placeholder user;
      adminUserValue = placeholder "ai.gateway.admin.user.${user}";
      adminPassValue = placeholder "ai.gateway.admin.pass.${user}";
    };

  templatesForUser = placeholder: user: {
    "llm-gw-config-${user}" = {
      content = builtins.toJSON (configJsonFor placeholder user);
      path = "/run/secrets/rendered/llm-gw-config-${user}.json";
      mode = "0400";
      owner = user;
    };
    # Готовый к отправке ключ доступа для клиентов (AI_GATEWAY_ACCESS_KEY_FILE):
    # с префиксом, без завершающего перевода строки — что в файле, то и в шлюзе.
    "llm-gw-access-key-${user}" = {
      content = accessKeyFor placeholder user;
      path = "/run/secrets/rendered/llm-gw-access-key-${user}";
      mode = "0400";
      owner = user;
    };
  };
in
{
  mkSecrets = lib.foldl' (acc: u: acc // secretsForUser u) { } mlUsers;
  mkTemplates = placeholder: lib.foldl' (acc: u: acc // templatesForUser placeholder u) { } mlUsers;
}
