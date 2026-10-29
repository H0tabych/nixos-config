# Фича: ml · Слот: — · Домен: presets · Классы: N+H · Для: пользователей с capability ml
# Контракт: STR-7 (пресет — только imports). compute-cache — R8.1; ai-facts,
# inference-service-ollama — R8.2; llm-gateway — R8.5; agents-tools — R8.6;
# code-context — R8.7 (AI_SUBSYSTEM.md §2.1).
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
    ];
  };
  flake.modules.homeManager.ml = {
    imports = [
      hm.llm-gateway
      hm.agents-tools
    ];
  };
}
