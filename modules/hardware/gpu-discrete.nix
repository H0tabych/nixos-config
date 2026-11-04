# Фича: gpu-discrete · Слот: — · Домен: hardware · Классы: N · Для: хостов с дискретной NVIDIA GPU
# Контракт: HOST-3, STO-5 (powerManagement нужен для гибернации), AI-RES-3, A5. Владеет
# драйвером и управлением питанием дискретного GPU (ARCHITECTURE.md §A.6: открытые модули
# ядра — архитектура Turing поддерживается; finegrained — под тестом энергопотребления и
# гибернации, RK4). Ход теста и его итог — docs/runbook/ai.md, раздел 8.
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
        open = true;
        modesetting.enable = true;
        powerManagement = {
          enable = true;
          # Этап А теста AI-A3. NVIDIA заявляет RTD3 в открытых модулях только с Ampere,
          # у нас Turing, поэтому результат нужно читать в
          # /proc/driver/nvidia/gpus/<шина>/power. Без suspended или при сбое гибернации
          # — этап Б (open = false) либо откат на false (RK4).
          finegrained = true;
        };
      };
    };
}
