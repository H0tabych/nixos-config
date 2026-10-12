# Фича: vcs-tools · Слот: — · Домен: shell · Классы: N · Для: всех хостов (base)
# Контракт: DEV-1, ARCH-11 (environment.systemPackages — для нужд системы):
# пакет; конфиг git — в dotfiles (приложение реестра, A.4; DOT-3). Симлинк
# ~/.config/git создаёт dotfiles-link.
# Только N-класс: git нужен nix-фетчеру input'ов (например, git+ssh dotfiles) до
# логина и активации home-manager, то есть это системная нужда. Дублирующий
# home.packages убран — пакет объявляется один раз (ARCH-5), а системный git
# доступен каждому пользователю хоста, включая пользователей без capability.
# Зависимости: —
_: {
  flake.modules.nixos.vcs-tools =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.git ];
    };
}
