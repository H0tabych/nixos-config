# Фича: game-optimizer-gamemode-gamescope · Слот: game-optimizer · Домен: gaming · Классы: N · Для: capability gaming
# Контракт: A.3 (слот game-optimizer → gamemode + gamescope). A10: запуск на
# дискретной GPU (offload) — gamescope передаёт переменные PRIME offload
# запускаемой игре (ARCHITECTURE.md §A.6: PRIME offload + nvidia-offload);
# запуск игры через gamescope (или nvidia-offload из gpu-hybrid) — ручная
# опция запуска в Steam/лаунчере, не предмет этой фичи (FEAT-6).
# AI-A4/AI-RES-5 (AI_SUBSYSTEM.md): хук игры — единственный владелец здесь,
# не в AI-фиче (FEAT-6). GameMode custom-start вызывает `inference-release`,
# если команда есть; на хостах без ml-пресета команды нет — хук молча ничего
# не делает (SHOULD, без assertion на AI-фичу, ARCH-3). Абсолютный путь, а не
# поиск в PATH: апстрим nixpkgs (programs.gamemode) принудительно (mkForce)
# обрезает PATH сервиса gamemoded до одного pkexec (security.wrapperDir),
# поэтому `command -v inference-release` в этом PATH никогда не находится —
# подтверждено живым запуском (журнал gamemoded, VRAM не освобождался).
# Зависимости: gpu-hybrid (hardware.nvidia.prime.offload.enable) — только assertion.
_: {
  flake.modules.nixos.game-optimizer-gamemode-gamescope =
    { config, ... }:
    {
      assertions = [
        {
          assertion = config.hardware.nvidia.prime.offload.enable;
          message = "фича game-optimizer-gamemode-gamescope требует gpu-hybrid (hardware.nvidia.prime.offload)";
        }
      ];

      programs.gamemode = {
        enable = true;
        settings.custom.start = "[ -x /run/current-system/sw/bin/inference-release ] && /run/current-system/sw/bin/inference-release || true";
      };

      programs.gamescope = {
        enable = true;
        env = {
          __NV_PRIME_RENDER_OFFLOAD = "1";
          __VK_LAYER_NV_optimus = "NVIDIA_only";
          __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        };
      };
    };
}
