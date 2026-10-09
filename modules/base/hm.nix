# Фича: hm · Слот: — · Домен: base · Классы: N · Для: всех хостов
# Контракт: ARCH-14 (один экземпляр nixpkgs с общими overlay и allowUnfree, A16).
# Зависимости: —
{ inputs, ... }:
{
  flake.modules.nixos.hm = {
    imports = [ inputs.home-manager.nixosModules.home-manager ];

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
    };
  };
}
