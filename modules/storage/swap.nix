# Фича: swap · Слот: — · Домен: storage · Классы: N · Для: хостов с гибернацией
# Контракт: STO-4 (swap-файл на отдельном томе без CoW, размер ≥ RAM),
# STO-5 (устройство resume и смещение swap-файла). Владеет swapDevices,
# boot.resumeDevice и параметром resume_offset.
#
# Создание файла — штатным механизмом NixOS (STO-4 допускает «средствами
# NixOS/disko либо btrfs filesystem mkswapfile»): юнит mkswap-* в
# nixos/modules/config/swap.nix сам определяет btrfs по stat -f и вызывает
# `btrfs filesystem mkswapfile --uuid clear`, что даёт файл без CoW и без
# контрольных сумм. Отдельная опция монтирования nodatacow поэтому не нужна
# и запрещена STO-1 — том /swap смонтирован с общими опциями ФС (storage/layout).
#
# resume_offset в kernelParams задаётся здесь вручную: boot.resumeDevice даёт
# только `resume=` (nixos/modules/system/boot/systemd/initrd.nix), смещение
# systemd-initrd сам не вычисляет. Значение считает `just hibernate-offset`
# по уже созданному файлу и записывает в my.host.resume.offset (STO-5);
# при пересоздании файла его нужно пересчитать.
#
# Пока смещение не задано (offset = null), swap работает как обычный swap:
# гибернация недоступна, hardware/sleep и hardware/power сами выбирают
# политику по flake.lib.host.hibernationReady (L-12).
# Зависимости: layout (том /swap и /dev/mapper/cryptroot), host-facts
# (my.host.swap.sizeMiB, my.host.resume.offset) — только чтение (ARCH-3).
_: {
  flake.modules.nixos.swap =
    { config, lib, ... }:
    {
      assertions = [
        {
          assertion = config.my.host.swap.sizeMiB != null;
          message = "фича swap требует my.host.swap.sizeMiB ≥ объёма RAM (STO-4)";
        }
      ];

      swapDevices = [
        {
          device = "/swap/swapfile";
          size = config.my.host.swap.sizeMiB;
        }
      ];

      # STO-5: устройство resume — расшифрованный контейнер с ФС, на которой
      # лежит файл, а не раздел и не сам файл. Имя маппера принадлежит фиче
      # layout, поэтому берётся не литералом, а по контракту STO-3 («при LUKS
      # fileSystems."/".device указывает на /dev/mapper/<имя>»): том /swap и
      # корень лежат в одном контейнере.
      boot.resumeDevice = config.fileSystems."/".device;

      boot.kernelParams = lib.optional (
        config.my.host.resume.offset != null
      ) "resume_offset=${toString config.my.host.resume.offset}";
    };
}
