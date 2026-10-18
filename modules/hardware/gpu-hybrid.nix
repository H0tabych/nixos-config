# Фича: gpu-hybrid · Слот: — · Домен: hardware · Классы: N · Для: хостов с гибридной графикой
# Контракт: DESK-5 (стабильные идентификаторы устройств, а не порядковые номера). Владеет
# PRIME offload: рендер на дискретной GPU по запросу (ARCHITECTURE.md §A.6: PRIME offload +
# nvidia-offload). Bus ID для PRIME вычисляется из факта хоста (шина PCI, подтверждённая
# по udev/lspci в host-facts), а не задаётся отдельной константой — это и есть «стабильный
# идентификатор», не завязанный на порядок перечисления карт (card0/card1).
# Зависимости: host-facts (my.host.gpu.*BusId) — только assertion и чтение значения (ARCH-3).
_: {
  flake.modules.nixos.gpu-hybrid =
    { config, lib, ... }:
    let
      gpu = config.my.host.gpu;

      # "0000:01:00.0" (lspci/udev, домен:шина:устройство.функция, hex) →
      # "PCI:1:0:0" (формат hardware.nvidia.prime.*BusId, decimal, домен опускается при 0).
      toNvidiaBusId =
        pciAddr:
        let
          m = builtins.match "([0-9a-fA-F]{4}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2})\\.([0-9a-fA-F])" pciAddr;
          hex = s: lib.fromHexString s;
          domain = hex (builtins.elemAt m 0);
          bus = hex (builtins.elemAt m 1);
          device = hex (builtins.elemAt m 2);
          func = hex (builtins.elemAt m 3);
        in
        assert lib.assertMsg (
          m != null
        ) "gpu-hybrid: некорректный формат PCI bus id в my.host.gpu: ${pciAddr}";
        "PCI:${toString bus}${
          lib.optionalString (domain != 0) "@${toString domain}"
        }:${toString device}:${toString func}";
    in
    {
      assertions = [
        {
          assertion = gpu.integratedBusId != null && gpu.discreteBusId != null;
          message = "фича gpu-hybrid требует my.host.gpu.integratedBusId и discreteBusId в составе хоста";
        }
      ];

      # DESK-5, L-6: устройства DRM адресуются стабильными идентификаторами, а не
      # порядковыми номерами cardN — те меняются между загрузками. Имена симлинков
      # без двоеточий, как требует A.6: AQ_DRM_DEVICES разделяет список
      # двоеточиями, поэтому ни пути by-path, ни PCI-адреса в имя не годятся.
      # KERNELS= сопоставляется с именем любого родительского устройства, то есть
      # с PCI-адресом карты из факта хоста.
      # Потребитель списка устройств композитора — конфиг композитора в dotfiles
      # (DOT-3). Сам список здесь не фиксируется: по DESK-5 он не включает
      # дискретную GPU, пока к её выходам ничего не подключено, а выходы
      # HDMI-A-1/DP-1 на этом хосте принадлежат дискретной
      # (docs/hosts/sgms-laptop.md §13) — то есть список динамический и требует
      # проверки с подключённым монитором (ROADMAP R5.7).
      #
      # *-render — те же шины, но минор render-нода (renderD12x), а не card
      # (режиссирования/KMS). ПРОВЕРЕНО на машине (R7.2): vaGetDriverNames()
      # (авто-определение драйвера libva) падает на card-ноде ("operation
      # failed") и mpv молча уходит на программное декодирование, а на
      # renderD128/129 определяется верно (iHD/nvidia по шине). Видеодекод —
      # потребитель именно render-нода (mpv/theme, APP-3), KMS — card-нода
      # (композитор, выше); отдельный симлинк, а не замена igpu/dgpu.
      services.udev.extraRules = ''
        SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="${gpu.integratedBusId}", SYMLINK+="dri/by-host/igpu"
        SUBSYSTEM=="drm", KERNEL=="card[0-9]*", KERNELS=="${gpu.discreteBusId}", SYMLINK+="dri/by-host/dgpu"
        SUBSYSTEM=="drm", KERNEL=="renderD[0-9]*", KERNELS=="${gpu.integratedBusId}", SYMLINK+="dri/by-host/igpu-render"
        SUBSYSTEM=="drm", KERNEL=="renderD[0-9]*", KERNELS=="${gpu.discreteBusId}", SYMLINK+="dri/by-host/dgpu-render"
      '';

      hardware.nvidia.prime = {
        offload = {
          enable = true;
          enableOffloadCmd = true;
        };
        intelBusId = toNvidiaBusId gpu.integratedBusId;
        nvidiaBusId = toNvidiaBusId gpu.discreteBusId;
      };
    };
}
