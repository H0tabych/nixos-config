# Фича: ml · Слот: — · Домен: presets · Классы: N+H · Для: пользователей с capability ml
# Контракт: STR-7 (пресет — только imports). compute-cache — R8.1; ai-facts,
# inference-service-ollama — R8.2; llm-gateway — R8.5, R9.16 (только nixos-класс, ADR-45); agents-tools — R8.6;
# code-context — R8.7 (AI_SUBSYSTEM.md §2.1); web-search-searxng, mcp-jira — R9.23 (слот web-search, AI-CTX-4; AI-GW-14).
# Зависимости: —
{ config, ... }:
let
  n = config.flake.modules.nixos;
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos.ml = {
    imports = [
      n.compute-cache
      n.ai-facts
      n.inference-service-ollama
      n.llm-gateway
      n.web-search-searxng
      n.mcp-jira
    ];
  };
  flake.modules.homeManager.ml = {
    imports = [
      hm.agents-tools
      hm.code-context
    ];
  };
}
