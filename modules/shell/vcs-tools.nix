# Фича: vcs-tools · Слот: — · Домен: shell · Классы: H · Для: user-base (ADR-32)
# Контракт: слот vcs-tools (ARCHITECTURE.md §6): пакет; конфиг git — в dotfiles
# (приложение реестра, A.4; DOT-3). Симлинк ~/.config/git создаёт dotfiles-link.
# Зависимости: —
_: {
  flake.modules.homeManager.vcs-tools = { pkgs, ... }: { home.packages = [ pkgs.git ]; };
}
