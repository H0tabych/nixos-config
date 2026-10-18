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
# Зависимости: —
_: {
  flake.modules.nixos.vcs-tools =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.git ];
    };

  flake.modules.homeManager.vcs-tools = { pkgs, ... }: {
    home.packages = [ pkgs.lazygit ];
  };
}
