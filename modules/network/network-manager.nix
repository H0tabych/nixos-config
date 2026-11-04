# Фича: network-manager · Слот: — · Домен: network · Классы: N · Для: всех хостов
# Контракт: — (управление сетевыми интерфейсами, ARCHITECTURE.md §6 — network);
# VPN 2.6: виртуальным интерфейсом туннеля в M2 менеджер не управляет.
# Зависимости: tunnel-facts (my.tunnel.*) — только чтение и только если подключена:
# фича есть на всех хостах, а пресет tunnel — нет (ARCH-3).
_: {
  flake.modules.nixos.network-manager =
    { config, lib, ... }:
    {
      networking.networkmanager = {
        enable = true;
        unmanaged = lib.optional (
          (config.my ? tunnel) && config.my.tunnel.mode == "m2"
        ) "interface-name:${config.my.tunnel.interface.name}";
      };
    };
}
