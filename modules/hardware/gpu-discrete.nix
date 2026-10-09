# Фича: gpu-discrete · Слот: — · Домен: hardware · Классы: N · Для: хостов с дискретной NVIDIA GPU
# Контракт: HOST-3, STO-5 (powerManagement нужен для гибернации). Владеет драйвером и
# управлением питанием дискретного GPU (ARCHITECTURE.md §A.6: открытые модули ядра —
# архитектура Turing поддерживается; finegrained — только после теста энергопотребления
# и гибернации, RK4).
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
          # Включать только после отдельного теста энергопотребления и гибернации (RK4).
          finegrained = false;
        };
      };
    };
}
