# Шаблон пресета (STR-7). Скопировать в modules/presets/<имя>.nix.
#
# Пресет: <имя> · Вид: <класс хоста | capability>
{ config, ... }:
let
  n = config.flake.modules;
in
{
  flake.modules.nixos.CHANGE_ME = {
    imports = with n.nixos; [ ];
  };
  flake.modules.homeManager.CHANGE_ME = {
    imports = with n.homeManager; [ ];
  };
}
