# Фича: containers · Слот: — · Домен: presets · Классы: N+H · Для: пользователей с capability containers
# Контракт: STR-7, USER-4. Рантайм — фича containers-docker (STRUCTURE.md §3:
# фича, реализующая capability, не носит имя capability).
# Зависимости: —
{ config, ... }:
let
  n = config.flake.modules.nixos;
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos.containers = {
    imports = [ n.containers-docker ];
  };
  flake.modules.homeManager.containers = {
    imports = [ hm.containers-docker ];
  };
}
