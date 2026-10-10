# Фича: vm · Слот: — · Домен: presets · Классы: N · Для: хостов класса vm
# Контракт: STR-7 (пресет — только imports). "Минимальный набор" по таблице §7
# ARCHITECTURE.md: синтетическая разметка/загрузчик вместо реальных (HOST-4).
# Зависимости: —
{ config, ... }:
let
  n = config.flake.modules.nixos;
in
{
  flake.modules.nixos.vm = {
    imports = [ n.vm-layout ];
  };
}
