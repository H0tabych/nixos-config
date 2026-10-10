# Фича: users · Слот: — · Домен: base · Классы: N · Для: всех хостов
# Контракт: USER-2, USER-3 (учётные записи + подключение HM-модулей по capability);
# ADR-32 (user-base подключается каждому пользователю независимо от capability).
# Зависимости: host-facts (my.host.users), реестр my.users (core/options.nix).
{ config, ... }:
let
  outer = config;
in
{
  flake.modules.nixos.users =
    { config, lib, ... }:
    let
      hostUsers = lib.getAttrs config.my.host.users outer.my.users;
      hm = outer.flake.modules.homeManager;
    in
    {
      users.users = lib.mapAttrs (_: u: {
        isNormalUser = true;
        inherit (u) uid;
        extraGroups = lib.optional u.admin "wheel";
      }) hostUsers;

      users.groups = lib.mapAttrs (_: u: {
        inherit (u) gid;
      }) hostUsers;

      home-manager.users = lib.mapAttrs (_: u: {
        # HOST-5: версия состояния HM по умолчанию берётся из my.host.stateVersion.
        home.stateVersion = config.my.host.stateVersion;
        imports =
          lib.optional (lib.hasAttr "user-base" hm) hm.user-base
          ++ lib.concatMap (c: lib.optional (lib.hasAttr c hm) hm.${c}) u.capabilities;
      }) hostUsers;
    };
}
