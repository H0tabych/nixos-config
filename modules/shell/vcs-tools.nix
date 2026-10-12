# Фича: vcs-tools · Слот: — · Домен: shell · Классы: N+H · Для: user-base (ADR-32)
# Контракт: слот vcs-tools (ARCHITECTURE.md §6): пакет; конфиг git — в dotfiles
# (приложение реестра, A.4; DOT-3). Симлинк ~/.config/git создаёт dotfiles-link.
# N — systemPackages: nix-фетчеру input'ов (например, git+ssh dotfiles) нужен git
# до логина и активации home-manager, не только внутри пользовательской сессии.
# Зависимости: —
_: {
  flake.modules.nixos.vcs-tools = { pkgs, ... }: { environment.systemPackages = [ pkgs.git ]; };
  flake.modules.homeManager.vcs-tools = { pkgs, ... }: { home.packages = [ pkgs.git ]; };
}
