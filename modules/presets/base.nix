# Фича: base · Слот: — · Домен: presets · Классы: N · Для: всех хостов класса base
# Контракт: STR-7 (пресет — только imports). sops, hardening, shell-zsh,
# env-manager-direnv, dotfiles-link добавятся по мере готовности (R3.1, R9.1, R4.2, R4.4).
# Зависимости: —
{ config, ... }:
let
  n = config.flake.modules.nixos;
in
{
  flake.modules.nixos.base = {
    imports = [
      n.nix-settings
      n.locale-keyboard
      n.users
      n.hm
      n.fonts
      n.host-facts
      n.ssh
      n.firewall
      n.network-manager
    ];
  };
}
