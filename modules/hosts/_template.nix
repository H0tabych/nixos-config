# Шаблон хоста (HOST-1, STR-8, чек-лист 18.3 Архитектуры).
# Скопировать в modules/hosts/<имя>.nix, заполнить факты, убрать неиспользуемое.
# Префикс `_` исключает файл из автоимпорта (ARCH-2), поэтому он не собирается.
#
# Допустимо здесь: imports, my.host.*, значения параметров подсистем
# (my.tunnel.policy.*, my.ai.*). Недопустимо: пакеты, сервисы, mkForce (FEAT-6).
# Имя хоста не должно совпадать с именем фичи или пресета (STR-4a); имена
# пресетов зарезервированы.
#
# Что ещё нужно сделать для нового хоста (18.3):
#   1. machines/<имя>/hardware.nix — сгенерировать (nixos-generate-config)
#   2. secrets/hosts/<имя>.yaml + правило в .sops.yaml (SEC-7)
#   3. docs/hosts/<имя>.md — физические характеристики железа
#   4. ключ хоста доставить до первой активации (SEC-12)
{ config, inputs, ... }:
let
  n = config.flake.modules.nixos;
in
{
  flake.nixosConfigurations.CHANGE_ME = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ n.CHANGE_ME ];
  };

  flake.modules.nixos.CHANGE_ME = {
    imports = [
      n.base # класс хоста: base + один из laptop/workstation/server/vm
      # n.laptop
      # n.desktop n.development n.office n.media   # capabilities
      # n.tunnel                                   # сетевая среда (не capability)
      # n.gpu-integrated n.gpu-discrete n.gpu-hybrid   # аппаратное — составом (HOST-3)
      # ../../machines/CHANGE_ME/hardware.nix          # исключение STR-9
    ];

    my.host = {
      name = "CHANGE_ME";
      class = "laptop";
      # HOST-5: релиз установщика; не обязан совпадать с каналом пакетов.
      stateVersion = "26.05";
      users = [ ];

      # Факты железа заполняются по docs/hosts/<имя>.md (R0.5).
      # gpu = { integratedBusId = "0000:00:02.0"; discreteBusId = "0000:01:00.0";
      #         vramGiB = 4; compute = "cuda"; computeCapability = "7.5"; };
      # battery = { present = true; capacityWh = 48; };
      # keyboardLayout = "us,ru";
      # outputs = [ { name = "internal"; connector = "eDP-1";
      #               width = 1920; height = 1080; refreshRate = 60; internal = true; } ];
      # disk.device = "/dev/disk/by-id/<стабильный-идентификатор>";
      # resume.offset — после создания swap-файла, `just hibernate-offset` (STO-5)
    };
  };
}
