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
        # GSP отключён: с ним RTD3 на Turing не включается. Проверено на машине 2026-11-05:
        # при GSP и proprietary — `Runtime D3 status: Not supported`, без GSP — `Enabled
        # (fine-grained)`, `runtime_status = suspended`, хотя условия README выполнены и так
        # (ноутбук, _PR0/_PR3 у PEG0, HM470, Turing, ядро 6.18).
        # gsp.enable = false в этом nixpkgs лишь не поставляет файлы прошивки; параметр
        # драйвера NixOS не задаёт (ПРОВЕРЕНО: NVreg_EnableGpuFirmware в nixos/ нет),
        # поэтому он выставлен явно ниже.
        gsp.enable = false;
        modesetting.enable = true;
        powerManagement = {
          enable = true;
          # Результат читать в /proc/driver/nvidia/gpus/<шина>/power. Сбой гибернации или
          # CUDA — откат на false (RK4).
          finegrained = true;
        };
      };

      boot.extraModprobeConfig = "options nvidia NVreg_EnableGpuFirmware=0";
    };
}
