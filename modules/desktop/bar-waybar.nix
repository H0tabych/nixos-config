# Фича: bar-waybar · Слот: bar · Домен: desktop · Классы: N · Для: capability desktop
# Контракт: SLOT-4 (демон — user-юнит на graphical-session.target). Класс N, а не H
# (отличие от ориентировочной таблицы STRUCTURE.md E.2): NixOS-модуль programs.waybar
# содержит только enable/package/systemd.target — без генератора конфига, в отличие
# от HM-модуля programs.waybar (ломает DOT-3 для приложения реестра). Конфиг — в
# dotfiles (DOT-3), cюда не входит.
# PATH юнита (DSN-S5, R6.8, исправление): юнит приходит из пакета (systemd.packages),
# без environment.PATH — наследует минимальный PATH systemd --user менеджера
# (coreutils/findutils/grep/sed/systemd, проверено на машине 2026-10-15), в нём
# нет ни bash (custom-модули waybar/scripts/* не стартуют: "env: bash: No such
# file or directory"), ни Home-Manager профиля (rofi/mako/swayosd-client).
# Опция — не serviceConfig.Environment (это Home Manager-стиль "ключ=значение"
# списком), а штатная systemd.user.services.<имя>.environment NixOS-модуля
# (attrsOf str → Environment=KEY=VALUE в юните; ПРОВЕРЕНО: прошлая попытка
# `Service.Environment` — ошибка сборки, такой опции нет). mkForce (ARCH-13):
# systemd/user.nix уже задаёт enableDefaultPath (минимальный PATH без bash и
# без профиля) обычным определением (не mkDefault), конфликт типа str без
# force — ПРОВЕРЕНО сборкой. %u/%h — специфайеры systemd (имя пользователя/
# домашний каталог), не константы хоста (ARCH-17).
# Зависимости: —
_: {
  flake.modules.nixos.bar-waybar =
    { lib, pkgs, ... }:
    {
      programs.waybar.enable = true;

      # Клик по рабочему столу (M24, исправление 2026-10-21). Hyprland 0.55.4 с
      # нативным Lua-конфигом исполняет payload сокета как Lua — подставляет его в
      # `return hl.dispatch(<payload>)` (ПРОВЕРЕНО: строка-шаблон есть в бинарнике,
      # а `hyprctl dispatch workspace 1` отвечает «')' expected near '1'»). Поэтому
      # легаси-строка waybar не исполняется, а Lua-форма работает: `hyprctl dispatch
      # "hl.dsp.focus({ workspace = N })"` → `ok` (ПРОВЕРЕНО живой пробой). Внешний
      # IPC при этом жив — чинить нужно одну жёстко вшитую строку waybar
      # (workspace.cpp:76), что и делает апстрим: Alexays/Waybar#5008, фикс в
      # PR #5013 смёржен в main, тегового релиза нет (последний — 0.15.0 от
      # 2026-02-06; в nixpkgs 26.05 и unstable тоже 0.15.0).
      # `lib.mkIf (version == "0.15.0")` — предохранитель: на любой другой версии
      # определение не применяется, обновление не блокируется и waybar берётся
      # штатный. Когда версия сменится — ЭТОТ БЛОК УДАЛИТЬ (фикс будет в апстриме).
      # `--replace-fail`, а не `--replace-quiet`: если исходник самой 0.15.0 поедет,
      # сборка упадёт громко, а не станет молчаливым no-op.
      # `(o.postPatch or "") +` — у пакета nixpkgs свой postPatch (подменяет /bin/sh
      # на bash из стора), затирать его нельзя.
      # Порядок override: опция объявлена через mkPackageOption с
      # `apply = pkg: pkg.override { systemdSupport = true; }` — этот `.override`
      # переприменяет наш `overrideAttrs` (ПРОВЕРЕНО сравнением drvPath: у патченого
      # пакета после apply другой .drv), так что патч не теряется.
      programs.waybar.package = lib.mkIf (pkgs.waybar.version == "0.15.0") (
        pkgs.waybar.overrideAttrs (o: {
          postPatch = (o.postPatch or "") + ''
            substituteInPlace src/modules/hyprland/workspace.cpp \
              --replace-fail '"dispatch workspace " + std::to_string(id())' \
                             '"dispatch hl.dsp.focus({workspace = " + std::to_string(id()) + "})"'
          '';
        })
      );

      systemd.user.services.waybar.environment.PATH =
        lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin:/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin:%h/.local/state/nix/profile/bin:/nix/var/nix/profiles/default/bin";
    };
}
