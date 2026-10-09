# Фича: sgms-laptop · Слот: — · Домен: hosts · Классы: N · Для: sgm
# Контракт: ARCH-4, HOST-1, STR-8. Композиция хоста + факты my.host.* (без пакетов и сервисов).
# Зависимости: host-facts (схема опций). Пресеты и machines/sgms-laptop/hardware.nix — с R2.6.
{ config, ... }:
let
  n = config.flake.modules.nixos;
in
{
  flake.modules.nixos.sgms-laptop = {
    imports = [ n.host-facts ];

    my.host = {
      name = "sgms-laptop";
      class = "laptop";

      gpu = {
        integratedBusId = "0000:00:02.0";
        discreteBusId = "0000:01:00.0";
        vramGiB = 4;
        compute = "cuda";
        computeCapability = "7.5";
      };

      battery = {
        present = true;
        capacityWh = 48;
      };

      inputDevices = [
        "AT Translated Set 2 keyboard"
        "ELAN1203:00 04F3:307A Touchpad"
        "Lid Switch"
        "Power Button"
        "Asus WMI hotkeys"
      ];

      outputs = [
        {
          name = "internal";
          width = 1920;
          height = 1080;
          refreshRate = 144;
          internal = true;
        }
      ];

      # Подтверждено lsblk + ls -l /dev/disk/by-id/ на машине (2026-10-10): единственный
      # NVMe, Intel SSDPEKNU512GZ (совпадает с §5 docs/hosts/sgms-laptop.md); by-id — для
      # устойчивости к порядку перечисления при декларативной разметке (STO-1).
      disk.device = "/dev/disk/by-id/nvme-INTEL_SSDPEKNU512GZ_PHKA237205CL512A";
    };
  };
}
