# Фича: gpu-integrated · Слот: — · Домен: hardware · Классы: N · Для: хостов со встроенной Intel GPU
# Контракт: HOST-3 (аппаратный состав — через наличие фичи в хосте). Владеет аппаратным
# ускорением видео встроенного GPU (ARCHITECTURE.md §6, строка hardware).
# Зависимости: host-facts (my.host.gpu.integratedBusId) — только assertion, не import (ARCH-3).
_: {
  flake.modules.nixos.gpu-integrated =
    { config, pkgs, ... }:
    {
      assertions = [
        {
          assertion = config.my.host.gpu.integratedBusId != null;
          message = "фича gpu-integrated требует my.host.gpu.integratedBusId в составе хоста";
        }
      ];

      hardware.graphics = {
        enable = true;
        # iHD (VA-API) — для UHD Graphics 630 (Comet Lake, Gen9.5), docs/hosts §3.2.
        extraPackages = [ pkgs.intel-media-driver ];
      };
    };
}
