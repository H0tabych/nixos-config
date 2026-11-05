# Фича: gpu-discrete · Слот: — · Домен: hardware · Классы: N · Для: хостов с дискретной NVIDIA GPU
# Контракт: HOST-3, STO-5 (powerManagement нужен для гибернации), AI-RES-3, A5. Владеет
# драйвером и управлением питанием дискретного GPU (ARCHITECTURE.md §A.6: проприетарные
# модули ядра, потому что RTD3 в открытых работает только с Ampere; finegrained — под
# тестом энергопотребления и гибернации, RK4). Ход теста и его итог — docs/runbook/ai.md,
# раздел 8.
# Зависимости: host-facts (my.host.gpu.discreteBusId/vramGiB) — только assertion (ARCH-3).
_: {
  flake.modules.nixos.gpu-discrete =
    { config, ... }:
    {
      assertions = [
        {
          assertion = config.my.host.gpu.discreteBusId != null;
          message = "фича gpu-discrete требует my.host.gpu.discreteBusId в составе хоста";
        }
        {
          assertion = config.my.host.gpu.vramGiB != null;
          message = "фича gpu-discrete требует my.host.gpu.vramGiB в составе хоста";
        }
      ];

      services.xserver.videoDrivers = [ "nvidia" ];

      hardware.nvidia = {
        # Этап Б теста AI-A3. Этап А (open = true, finegrained = true) дал
        # `Runtime D3 status: Not supported` на GTX 1650 (Turing, драйвер 595.71.05,
        # 2026-11-05): NVIDIA заявляет RTD3 в открытых модулях только с Ampere. Проприетарные
        # модули Turing поддерживают.
        open = false;
        modesetting.enable = true;
        powerManagement = {
          enable = true;
          # Результат читать в /proc/driver/nvidia/gpus/<шина>/power. Если и здесь не
          # suspended, следующий шаг — отключить GSP (hardware.nvidia.gsp.enable = false),
          # затем откат на false (RK4).
          finegrained = true;
        };
      };
    };
}
