# Фича: vcs-tools · Слот: — · Домен: shell · Классы: N+H · Для: всех хостов (base) / всех пользователей (user-base)
# Контракт: DEV-1, ARCH-11 (environment.systemPackages — для нужд системы):
# пакет git; конфиг git — в dotfiles (приложение реестра, A.4; DOT-3). Симлинк
# ~/.config/git создаёт dotfiles-link.
# N-класс (git): git нужен nix-фетчеру input'ов (например, git+ssh dotfiles) до
# логина и активации home-manager, то есть это системная нужда. Дублирующий
# home.packages убран — пакет объявляется один раз (ARCH-5), а системный git
# доступен каждому пользователю хоста, включая пользователей без capability.
# H-класс (lazygit): сопутствующая утилита VCS без системной нужды — TUI,
# нужен только после логина; конфиг — в dotfiles (A.4), цвета — из генератора
# палитры (DESIGN_SYSTEM.md П.3.5).
# Идентичность (SEC-10): ~/.config/machine.d/git-identity (DOT-5) — из реестра
# my.users.<имя>.git (имя и анонимизированный адрес хостинга; они публичны по
# смыслу — попадают в каждый коммит). Файл лежит в хранилище, а не в sops: он
# должен читаться и внутри песочницы агентов (AI-A12 — коммит агента проходит),
# куда /run/secrets не попадает. Без обоих полей файл не создаётся.
# Зависимости: core/options (my.users.*, my.host.users) — только чтение (ARCH-3).
{ config, lib, ... }:
let
  outer = config;
in
{
  flake.modules.nixos.vcs-tools =
    { config, pkgs, ... }:
    let
      identified = lib.filter (
        u:
        let
          g = outer.my.users.${u}.git;
        in
        g.name != null && g.email != null
      ) config.my.host.users;
    in
    {
      environment.systemPackages = [ pkgs.git ];

      systemd.tmpfiles.rules = map (
        user:
        let
          g = outer.my.users.${user}.git;
        in
        "L+ /home/${user}/.config/machine.d/git-identity - - - - ${pkgs.writeText "git-identity" ''
          # Сгенерировано Nix (vcs-tools, SEC-10) из my.users.<имя>.git — не редактируйте руками.
          [user]
              name = ${g.name}
              email = ${g.email}
        ''}"
      ) identified;
    };

  flake.modules.homeManager.vcs-tools = { pkgs, ... }: {
    home.packages = [ pkgs.lazygit ];
  };
}
