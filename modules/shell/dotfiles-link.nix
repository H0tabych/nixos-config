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
# Зависимости: host-facts (my.host.{outputs,battery,gpu,keyboardLayout,users}),
# core/options (my.users.<имя>.dotfiles.source) — только чтение значений (ARCH-3).
{
  config,
  inputs,
  lib,
  ...
}:
let
  outer = config;

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

      monitorLines =
        if host.outputs == [ ] then
          "monitor=,preferred,auto,1\n"
        else
          lib.concatMapStrings (
            o: "monitor=,${toString o.width}x${toString o.height}@${toString o.refreshRate},auto,1\n"
          ) host.outputs;

      machineFiles = {
        "hypr-monitors.conf" = ''
          # Сгенерировано Nix (dotfiles-link, DOT-5) из my.host.outputs — не редактируйте руками.
        ''
        + monitorLines;

        "hypr-input.conf" = ''
          # Сгенерировано Nix (dotfiles-link, DOT-5) из my.host.keyboardLayout (DESK-7).
          input {
              kb_layout = ${host.keyboardLayout}
              kb_options = grp:alt_shift_toggle
          }
        '';

        "launch-prefix" = ''
          # Префикс запуска графических приложений (DESK-2). Механизм сессии —
          # UWSM (session-hyprland, R4.3): приложения из лаунчера/бара получают
          # прокси-переменные и остальное окружение сессии через `uwsm app --`.
          LAUNCH_PREFIX=uwsm app --
        '';

        "gpu-env" = ''
          # Сгенерировано Nix (dotfiles-link, DOT-5) из my.host.gpu — не редактируйте руками.
          GPU_INTEGRATED_BUS_ID=${toString host.gpu.integratedBusId}
          GPU_DISCRETE_BUS_ID=${toString host.gpu.discreteBusId}
          GPU_VRAM_GIB=${toString host.gpu.vramGiB}
        '';

        "battery-info" = ''
          # Сгенерировано Nix (dotfiles-link, DOT-5) из my.host.battery. Имя устройства
          # (/sys/class/power_supply/BAT*) не подтверждено — docs/hosts/sgms-laptop.md §8.
          BATTERY_PRESENT=${if host.battery.present then "1" else "0"}
          BATTERY_CAPACITY_WH=${toString host.battery.capacityWh}
        '';
      };
    in
    {
      systemd.tmpfiles.rules = lib.concatMap (
        user:
        [ "d /home/${user}/.config/machine.d 0755 ${user} ${user} - -" ]
        ++ lib.mapAttrsToList (
          name: text: "L+ /home/${user}/.config/machine.d/${name} - - - - ${pkgs.writeText name text}"
        ) machineFiles
      ) host.users;
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
