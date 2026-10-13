# Фича: sgms-laptop · Слот: — · Домен: hosts · Классы: N · Для: sgm
# Контракт: ARCH-4, HOST-1, STR-8. Композиция хоста + факты my.host.* (без пакетов и сервисов).
# Зависимости: presets base/laptop/desktop/development/media/tunnel; gpu-*, vpn-client
# подключаются прямо из хоста (HOST-3, персональная фича, не для класса laptop);
# machines/sgms-laptop/hardware.nix — исключение STR-9.
{ config, inputs, ... }:
let
  n = config.flake.modules.nixos;
in
{
  flake.nixosConfigurations.sgms-laptop = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ n.sgms-laptop ];
  };

  flake.modules.nixos.sgms-laptop = {
    imports = [
      n.base
      n.laptop
      n.desktop
      n.development
      n.media
      n.gpu-integrated
      n.gpu-discrete
      n.gpu-hybrid
      n.tunnel
      n.vpn-client
      ../../machines/sgms-laptop/hardware.nix
    ];

    my.host = {
      name = "sgms-laptop";
      class = "laptop";
      # Релиз установщика по R0.1; не обязан совпадать с каналом пакетов (HOST-5).
      stateVersion = "26.05";
      users = [ "sgm" ];

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

      keyboardLayout = "us,ru";

      outputs = [
        {
          name = "internal";
          # Подтверждено логом waybar на хосте (2026-10-12): "Bar configured ... for
          # output: eDP-1" — встроенная панель.
          connector = "eDP-1";
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

      # STO-4: ≥ объёма RAM (24 ГиБ = 16+8, docs/hosts/sgms-laptop.md §4) с
      # запасом на рост сжатых страниц при гибернации → 28 ГиБ.
      # При замене планок пересчитать и пересоздать файл (затем resume.offset).
      swap.sizeMiB = 28672;

      # STO-5: смещение swap-файла. Считается на машине по уже созданному файлу
      # (`just hibernate-offset`) и пересчитывается при его пересоздании.
      # ПРОВЕРИТЬ: значение ниже — заполняется после первого прогона R5.1.
      # resume.offset = null;
      resume.offset = 15787436;
    };

    # Режим туннеля остаётся m1 (умолчание tunnel-facts) намеренно: по ROADMAP
    # R5.4 переключение на m2 — ПОСЛЕДНЕЕ действие шага, и только после гейта
    # 7.3 (M2-1…M2-9), который проверяется на машине после приёмки гибернации
    # (R5.1, критерий M2-4). До этого dns-resolver и killswitch собраны, но
    # неактивны — обе фичи включаются по my.tunnel.mode.
    my.tunnel = {
      # Корпоративный split-horizon (VPN-DNS-1, класс scoped; ADR-34 — зоны
      # вкладываются в dns-resolver, а не пишутся vpn-client'ом).
      # Данные публичные (SEC-2 класс C, VPN-RTE-1): адрес внутреннего резолвера
      # и имена зон — не секрет, секрет только учётные данные (vpnClient.credentials).
      # link: в assets/vpn-client/sgms-laptop.ovpn задан `dev tun` → первый
      # свободный интерфейс tun0. Опущенный link по VPN-DNS-1 — отказ.
      dns.scopedZones = [
        {
          zones = [
            "cs.local"
            "controlsystems.ru"
            "metasfera.ru"
          ];
          server = "10.0.1.252";
          link = "tun0";
        }
      ];

      # VPN-KS-2: корпоративный линк исключён из kill switch — иначе рабочие
      # ресурсы стали бы недоступны при поднятом туннеле (§2.6, сосуществование).
      killswitch.allowedInterfaces = [ "tun0" ];
    };
  };
}
