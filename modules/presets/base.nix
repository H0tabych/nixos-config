# Фича: base · Слот: — · Домен: presets · Классы: N · Для: всех хостов класса base
# Контракт: STR-7 (пресет — только imports). hardening добавится в R9.1.
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
      n.sops
      n.ssh
      n.firewall
      n.network-manager
      n.dotfiles-link
      n.shell-zsh
      n.env-manager-direnv
      n.vcs-tools
      n.search-tools
      n.prompt-starship
    ];
  };
}
