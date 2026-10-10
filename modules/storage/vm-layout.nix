# Фича: vm-layout · Слот: — · Домен: storage · Классы: N · Для: хостов класса vm
# Контракт: HOST-4. Синтетические fileSystems."/" и загрузчик — только чтобы
# прошли общие assertions NixOS (top-level.nix) при вычислении
# system.build.toplevel. Реальная разметка (STO-1, фича layout) сюда не
# относится: класс vm не устанавливается на железо, а запускается через
# nixos-rebuild build-vm, который переопределяет fileSystems собственным
# диском (lib.mkVMOverride в qemu-vm.nix).
# Зависимости: —
_: {
  flake.modules.nixos.vm-layout = {
    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = false;
  };
}
