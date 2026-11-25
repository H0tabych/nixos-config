# Фича: agents-keys · Слот: — · Домен: ai · Классы: N · Для: пользователей с capability ml
# Контракт: AI_SUBSYSTEM.md §2.5, AI-AGT-9, ADR-051 (агент ходит к провайдеру в родном протоколе
# напрямую, без посредника-шлюза). Ключ провайдера для агента: секрет из sops пользователя
# (`my.ai.agentKeys.<агент>.sopsKey`) отдаётся ему же файлом 0400 в `/run/secrets` —
# лаунчер читает файл снаружи песочницы и передаёт ЗНАЧЕНИЕМ в окружение агента (`--pass-env`,
# AI-SBX-3); сама песочница `/run/secrets` не видит (AI-SBX-1). Агент видит ключ провайдера —
# цена решения ADR-051: потолок убытка — предоплата у провайдера.
# AI-CMP-4: машинный слой пользователя получает только ПУТИ файлов — значений там нет (SEC-4/A3);
# файл `~/.config/machine.d/ai-agents-env` пишется из этого nixos-модуля через home-manager.users
# (прецедент — llm-gateway), поэтому HM-части у фичи нет.
# Зависимости: ai-facts (my.ai.agentKeys), host-facts (my.host.users), users
# (my.users.*.capabilities) — только чтение my.*, не импорт (ARCH-3).
{ config, lib, ... }:
let
  outer = config;
  secretsFile = outer.flake.lib.repo.secrets;
  # Имя переменной с путём файла ключа агента: `dsh` → `AI_AGENT_KEYFILE_DSH`.
  varOf = agent: "AI_AGENT_KEYFILE_" + lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] agent);
in
{
  flake.modules.nixos.agents-keys =
    { config, ... }:
    let
      keys = config.my.ai.agentKeys;
      mlUsers = lib.filter (u: lib.elem "ml" outer.my.users.${u}.capabilities) config.my.host.users;
      secretName = agent: user: "ai.agents.${agent}.${user}";
    in
    {
      sops.secrets = lib.listToAttrs (
        lib.concatMap (
          user:
          lib.mapAttrsToList (
            agent: k:
            lib.nameValuePair (secretName agent user) {
              key = k.sopsKey;
              sopsFile = secretsFile "users/${user}.yaml";
              owner = user;
              mode = "0400";
            }
          ) keys
        ) mlUsers
      );

      home-manager.users = lib.genAttrs mlUsers (user: {
        home.file.".config/machine.d/ai-agents-env".text =
          "# Сгенерировано Nix (agents-keys, AI-CMP-4) — не редактируйте руками.\n"
          + lib.concatStrings (
            lib.mapAttrsToList (
              agent: _: "export ${varOf agent}=\"${config.sops.secrets.${secretName agent user}.path}\"\n"
            ) keys
          );
      });
    };
}
