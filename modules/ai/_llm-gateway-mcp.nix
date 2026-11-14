# Приватная часть: llm-gateway · Владелец: modules/ai/llm-gateway.nix (STR-6)
# Чистая функция: политика хоста `my.ai.gateway.mcp` → MCP-серверы шлюза (AI-GW-14) и права
# ключей доступа на их инструменты. Отдельным файлом: шаблон конфига шлюза у предела C6.
#
# Поля — по схеме Bifrost (transports/config.schema.json, тег transports/v2.1.0):
#   - mcp.client_configs[] — клиент: `connection_type` stdio|http, `stdio_config`
#     {command,args,envs} или `connection_string` + `auth_type = headers` + `headers`;
#   - virtual_keys[].mcp_configs[] — {mcp_client_name, tools_to_execute}: без записи
#     инструментов сервера ключ не видит (`[]` — запрещено всё, `["*"]` — всё).
# Имя клиента — без дефисов (ValidateMCPClientName в core/mcp/utils.go, ПРОВЕРЕНО по исходникам
# 2026-11-14): дефис нейтрального id заменяется подчёркиванием.
#
# Секреты. http: в заголовке метка `@MCP_<id>@` — её подставляет служба (jq), как ключи
# провайдеров. stdio: `envs` Bifrost принимает лишь имена (из окружения процесса) или
# `ИМЯ=значение`, метки туда не попадают; поэтому обёртка читает секрет из учётных данных
# службы (`$CREDENTIALS_DIRECTORY/mcp-<id>`, LoadCredential) и кладёт его в переменную сервера
# сама. Дочерний процесс наследует окружение шлюза (mcp-go: `os.Environ()` + `envs`, ПРОВЕРИТЬ
# ВМ-тестом) — отсюда CREDENTIALS_DIRECTORY и STATE_DIRECTORY. Значение секрета в argv и в
# конфиге не попадает.
# AI-GW-14: ключ `offline` инструментов не получает; `online` — только перечисленные агенту.
{
  lib,
  pkgs,
}:
{
  policy, # my.ai.gateway.mcp: id → сервер
  agents, # my.ai.gateway.agents: агент → { mcp = [ id ]; … }
}:
let
  clientName = lib.replaceStrings [ "-" ] [ "_" ];

  # stdio-сервер всегда запускается обёрткой: свой HOME в состоянии службы (DynamicUser: каталога
  # пользователя нет), несекретное окружение, секрет из учётных данных.
  wrapper =
    id: s:
    pkgs.writeShellScript "mcp-${id}" ''
      set -eu
      export HOME="''${STATE_DIRECTORY:?}/mcp-home"
      mkdir -p "$HOME"
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") s.env
      )}
      ${lib.optionalString (s.secret && s.secretEnv != null) ''
        ${s.secretEnv}=$(cat "''${CREDENTIALS_DIRECTORY:?}/mcp-${id}")
        export ${s.secretEnv}
      ''}
      exec ${lib.escapeShellArg s.command} "$@"
    '';

  client =
    id: s:
    {
      client_id = clientName id;
      name = clientName id;
      tools_to_execute = [ "*" ];
    }
    // (
      if s.type == "stdio" then
        {
          connection_type = "stdio";
          auth_type = "none";
          stdio_config = {
            command = "${wrapper id s}";
            inherit (s) args;
            envs = [ ];
          };
        }
      else
        {
          connection_type = "http";
          connection_string = s.url;
          auth_type = "headers";
          headers =
            s.headers // lib.optionalAttrs s.secret { ${s.secretHeader} = "${s.secretPrefix}@MCP_${id}@"; };
        }
    );
  clients = lib.mapAttrsToList client policy;
in
{
  # Раздел `mcp` конфига шлюза. Инструменты в запросы вывода не подмешиваются: агент берёт их
  # сам через /mcp.
  section = {
    client_configs = clients;
    tool_manager_config.disable_auto_tool_inject = true;
  };
  # Серверы с секретом: службе нужны учётные данные и метки подстановки; `name` — имя клиента
  # в конфиге шлюза (для вычёркивания клиента без секрета).
  secrets = lib.mapAttrsToList (id: _: {
    inherit id;
    name = clientName id;
  }) (lib.filterAttrs (_: s: s.secret) policy);
  # Права ключа `<агент>-<режим>` на инструменты (AI-GW-14).
  keys =
    agent: mode:
    lib.optionals (mode == "online") (
      map (id: {
        mcp_client_name = clientName id;
        tools_to_execute = [ "*" ];
      }) (agents.${agent}.mcp or [ ])
    );
}
