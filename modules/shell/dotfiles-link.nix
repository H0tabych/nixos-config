# Фича: dotfiles-link · Слот: — · Домен: shell · Классы: N+H · Для: user-base (ADR-32)
# Контракт: DOT-4, DOT-5, DOT-6; A14 (символические ссылки на /nix/store в ~/.config
# разрешены только здесь и в файлах менеджера сессии). N — реальный каталог
# ~/.config/machine.d и его содержимое (факты my.host.*, не из dotfiles, DOT-5). H —
# символические ссылки ~/.config/<app> → рабочая копия dotfiles (mkOutOfStoreSymlink).
# Список приложений берётся из закреплённого input dotfiles (а не живого
# dotfiles.source): pathExists по произвольному внешнему пути недопустим в pure eval;
# ссылка создаётся безусловно и становится рабочей без пересборки, когда каталог
# появляется в рабочей копии (DOT-4 — "без приложения — пропуск" про ещё
# не подтянутый nix flake update, а не про падение активации).
# Зависимости: host-facts, core/options (my.users.*) — только чтение (ARCH-3).
{
  config,
  inputs,
  lib,
  ...
}:
let
  outer = config;

  # USER-5: системные интеграции «на пользователя» применяются к пересечению
  # my.host.users и пользователей с нужной capability.
  withCap = cap: lib.attrNames (lib.filterAttrs (_: u: lib.elem cap u.capabilities) outer.my.users);

  # Не-приложения на верхнем уровне репозитория dotfiles (REGISTRY.md их не содержит).
  nonAppEntries = [
    ".git"
    ".github"
    ".gitignore"
    "install.sh"
    "README.md"
    "REGISTRY.md"
    "machine.d.example"
    "theme"
    "checks"
  ];

  # Каталог репозитория → целевое имя в ~/.config (REGISTRY.md: у mangohud
  # нестандартный регистр целевого каталога).
  targetNameOverrides = {
    mangohud = "MangoHud";
  };

  dotfilesEntries = builtins.readDir inputs.dotfiles;
  appDirs = builtins.filter (
    name: dotfilesEntries.${name} == "directory" && !builtins.elem name nonAppEntries
  ) (builtins.attrNames dotfilesEntries);
  apps = builtins.listToAttrs (
    map (dir: {
      name = dir;
      value = targetNameOverrides.${dir} or dir;
    }) appDirs
  );

  # DSN-S5 (R6.8, исправление): имя файла обоев активного варианта — из того же
  # закреплённого input dotfiles, которым уже пользуется theme.nix (DSN-TOK-6).
  # Абсолютный путь к самим обоям собирается ниже из dotfiles.source пользователя
  # (DOT-5: факт установки, не из dotfiles) — hyprlang не резолвит $HOME сам
  # по себе (ПРОВЕРЕНО на машине 2026-10-15: hyprpaper молча не находит обои).
  palette = builtins.fromTOML (builtins.readFile "${inputs.dotfiles}/theme/palette.toml");
  wallpaperFile = palette.variant.${palette.active}.wallpaper.file;
in
{
  # Для `just dotfiles-clone` (R4.6): путь нужен вне Nix-сборки, поэтому
  # читается через `nix eval`, а не дублируется в скрипте (STR-11).
  flake.dotfilesClonePaths = lib.filterAttrs (_: v: v != null) (
    builtins.mapAttrs (_: u: u.dotfiles.source) outer.my.users
  );

  flake.modules.nixos.dotfiles-link =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      host = config.my.host;
      machineFiles = (import ./_dotfiles-link-machine.nix { inherit lib; }).mkMachineFiles {
        inherit host;
      };
      desktopUsers = lib.intersectLists host.users (withCap "desktop");
    in
    {
      # ~/.config объявлен явно: неявно создаваемые systemd-tmpfiles родительские
      # каталоги достаются вызывающему процессу (root) — chown применяется только
      # к последнему компоненту пути. На чистой установке (18.9) ~/.config ещё
      # нет, systemd-tmpfiles-setup идёт раньше home-manager-<user>.service, и
      # тот (User=<user>) не смог бы записать ~/.config/*.
      # Владелец обоих каталогов — эта фича (DOT-5); shell-zsh кладёт файл в
      # machine.d, но каталогами не владеет (ARCH-5).
      systemd.tmpfiles.rules =
        lib.concatMap (user: [
          "d /home/${user}/.config 0755 ${user} ${user} - -"
          "d /home/${user}/.config/machine.d 0755 ${user} ${user} - -"
        ]) host.users
        # machineFiles — значения рабочего стола, поэтому только пользователям с
        # capability desktop (USER-5), а не всем пользователям хоста.
        ++ lib.concatMap (
          user:
          lib.mapAttrsToList (
            name: text: "L+ /home/${user}/.config/machine.d/${name} - - - - ${pkgs.writeText name text}"
          ) machineFiles
        ) desktopUsers
        # Путь к обоям зависит от dotfiles.source конкретного пользователя (не
        # только от фактов хоста), поэтому отдельно от machineFiles выше.
        ++ lib.concatMap (
          user:
          let
            src = outer.my.users.${user}.dotfiles.source or null;
          in
          lib.optional (src != null)
            "L+ /home/${user}/.config/machine.d/hypr-wallpaper.conf - - - - ${pkgs.writeText "hypr-wallpaper.conf" ''
              # Сгенерировано Nix (dotfiles-link, DOT-5) из my.users.<user>.dotfiles.source
              # и theme/palette.toml (input dotfiles) — не редактируйте руками.
              $wallpaper = ${src}/theme/wallpapers/${wallpaperFile}
            ''}"
        ) desktopUsers;
    };

  flake.modules.homeManager.dotfiles-link =
    { config, lib, ... }:
    let
      source = outer.my.users.${config.home.username}.dotfiles.source or null;
    in
    lib.mkIf (source != null) {
      home.file = lib.mapAttrs' (
        dir: target:
        lib.nameValuePair ".config/${target}" {
          source = config.lib.file.mkOutOfStoreSymlink "${source}/${dir}";
        }
      ) apps;
    };
}
