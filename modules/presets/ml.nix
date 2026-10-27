# Фича: ml · Слот: — · Домен: presets · Классы: N · Для: пользователей с capability ml
# Контракт: STR-7 (пресет — только imports). compute-cache — R8.1; ai-facts,
# inference-service-ollama — R8.2; llm-gateway — R8.5; homeManager-часть
# (agents-tools, code-context, llm-gateway) — R8.5–R8.7 (AI_SUBSYSTEM.md §2.1).
# Зависимости: —
{ config, ... }:
let
  n = config.flake.modules.nixos;
in
{
  flake.modules.nixos.ml = {
    imports = [
      n.compute-cache
      n.ai-facts
      n.inference-service-ollama
    ];
  };
}
