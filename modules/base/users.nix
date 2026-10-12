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
      # USER-2: хост выбирает подмножество реестра. Незарегистрированное имя
      # давало сырое `attribute '<имя>' missing` из lib.getAttrs без указания на
      # причину, поэтому список сверяется заранее.
      unknownUsers = lib.subtractLists (lib.attrNames outer.my.users) config.my.host.users;
      hostUsers = lib.getAttrs (lib.subtractLists unknownUsers config.my.host.users) outer.my.users;
      hm = outer.flake.modules.homeManager;
    in
    {
      assertions = [
        {
          assertion = unknownUsers == [ ];
          message =
            "my.host.users содержит пользователей без записи в my.users (USER-1):"
            + " ${lib.concatStringsSep ", " unknownUsers}."
            + " Добавьте modules/users/<имя>.nix либо уберите имя из хоста.";
        }
      ];

      users.users = lib.mapAttrs (name: u: {
        isNormalUser = true;
        inherit (u) uid;
        # Основная группа — личная (gid ниже), а не дефолтная "users" (R2.2).
        group = name;
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
