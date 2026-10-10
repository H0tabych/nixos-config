# Фича: ci-vm · Слот: — · Домен: hosts · Классы: N · Для: CI
# Контракт: ARCH-4, HOST-1, HOST-4. Хост класса vm — доказательство переносимости
# общих фич (не завязаны на конкретное железо); не устанавливается на реальную
# машину, поэтому без gpu-* и без machines/ci-vm/hardware.nix (HOST-3 сюда не
# относится — это про отсутствие привязки к железу). Разметка — синтетическая,
# из пресета vm (modules/storage/vm-layout.nix), не реальный disko (STO-1).
# Зависимости: пресеты base, vm.
{ config, inputs, ... }:
let
  n = config.flake.modules.nixos;
in
{
  flake.nixosConfigurations.ci-vm = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ n.ci-vm ];
  };

  flake.modules.nixos.ci-vm = {
    imports = [
      n.base
      n.vm
    ];

    my.host = {
      name = "ci-vm";
      class = "vm";
      stateVersion = "26.05";
      users = [ ];
    };
  };
}
