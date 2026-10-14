# Фича: containers-docker · Слот: containers · Домен: dev · Классы: N+H · Для: capability containers
# Контракт: DEV-6 (один рантайм; доступ — пересечение my.host.users и
# пользователей с capability containers, USER-5; членство в группе docker
# равносильно правам root — принято осознанно; автоочистка). GPU в
# контейнерах — отдельная фича container-gpu-nvidia (STRUCTURE E.2), не здесь.
# STO-11: образы и слои — подкаталог тома вне снимков и бэкапа
# (/var/lib/nosnapshot, storage/layout), иначе растут снимки корня.
# Зависимости: layout (том /var/lib/nosnapshot), my.users.<имя>.capabilities —
# через config, без импорта фич (ARCH-3).
{ config, lib, ... }:
let
  outer = config;
  usersWithCap = lib.attrNames (
    lib.filterAttrs (_: u: lib.elem "containers" u.capabilities) outer.my.users
  );
in
{
  flake.modules.nixos.containers-docker =
    { config, lib, ... }:
    let
      allowedUsers = lib.intersectLists config.my.host.users usersWithCap;
    in
    {
      virtualisation.docker = {
        enable = true;
        daemon.settings.data-root = "/var/lib/nosnapshot/docker";
        autoPrune.enable = true;
      };

      users.users = lib.genAttrs allowedUsers (_: {
        extraGroups = [ "docker" ];
      });
    };

  flake.modules.homeManager.containers-docker = { pkgs, ... }: {
    home.packages = [ pkgs.docker-compose ];
  };
}
