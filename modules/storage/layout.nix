# Фича: layout · Слот: — · Домен: storage · Классы: N · Для: всех хостов
# Контракт: STO-1 (декларативная разметка, раздельные тома), STO-2 (шифрование
# MUST), STO-3 (systemd-initrd, /dev/mapper). Подтома: корень, @home, @nix,
# логи, снимки, данные сервисов вне снимков/бэкапа, swap (сам swap-файл —
# storage/swap, R5.1, STO-4).
# Зависимости: host-facts (my.host.disk.device); assertions ниже.
{ inputs, ... }:
{
  flake.modules.nixos.layout =
    { config, ... }:
    let
      # STO-1: один набор опций монтирования на весь том — иначе L-11
      # (опции Btrfs общие для ФС, "по томам" ведут себя неожиданно).
      btrfsMountOptions = [
        "compress=zstd"
        "noatime"
      ];
    in
    {
      imports = [ inputs.disko.nixosModules.disko ];

      assertions = [
        {
          assertion = config.my.host.disk.device != null;
          message = "фича layout требует my.host.disk.device (STO-1)";
        }
      ];

      # STO-3: systemd в initrd — явно, не только дефолт релиза (риск R-05).
      boot.initrd.systemd.enable = true;
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      disko.devices.disk.main = {
        type = "disk";
        device = config.my.host.disk.device;
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                # STO-2: LUKS2 явно — не полагаемся на дефолт cryptsetup.
                extraFormatArgs = [
                  "--type"
                  "luks2"
                ];
                # TRIM через LUKS — диск NVMe SSD.
                settings.allowDiscards = true;
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    # Не "/root" — чтобы не путать с домашним каталогом root.
                    "/rootfs" = {
                      mountpoint = "/";
                      mountOptions = btrfsMountOptions;
                    };
                    "/home" = {
                      mountpoint = "/home";
                      mountOptions = btrfsMountOptions;
                    };
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = btrfsMountOptions;
                    };
                    "/log" = {
                      mountpoint = "/var/log";
                      mountOptions = btrfsMountOptions;
                    };
                    # Инструмент снимков выбирается позже (STO-9); здесь —
                    # только зарезервированный том.
                    "/snapshots" = {
                      mountpoint = "/.snapshots";
                      mountOptions = btrfsMountOptions;
                    };
                    # Данные сервисов вне снимков и бэкапа (STO-1, STO-11):
                    # модели, игровая библиотека, образы контейнеров —
                    # подкаталогами, без собственных опций монтирования
                    # (AI_SUBSYSTEM AI-INF-8).
                    "/data" = {
                      mountpoint = "/var/lib/nosnapshot";
                      mountOptions = btrfsMountOptions;
                    };
                    # Swap-файл создаёт storage/swap (R5.1, STO-4) —
                    # здесь только том, без swap.swapfile.
                    "/swap" = {
                      mountpoint = "/swap";
                      mountOptions = btrfsMountOptions;
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
}
