# Фича: search-tools · Слот: — · Домен: shell · Классы: N · Для: всех хостов (base)
# Контракт: DEV-1 («быстрый поиск» — часть глобального минимума, тот же пункт,
# что VCS и утилиты). fzf — нечёткий поиск (интеграция zsh — dotfiles,
# `fzf --zsh`, без путей из машинного слоя: механизм берёт из PATH, работает
# одинаково на любом дистрибутиве); ripgrep/fd — быстрый поиск по содержимому
# и файлам, backend для `FZF_DEFAULT_COMMAND` (dotfiles, статика). N-класс —
# как vcs-tools: простые бинарники без мест, нужны каждому пользователю хоста,
# не только capability.
# Тема fzf (DESIGN_SYSTEM.md П.3.5: `--color` из ролей, `bg:-1`) — генератор
# в dotfiles (`theme/gen/templates/fzf-theme.zsh.tmpl`), не здесь.
# Зависимости: —
_: {
  flake.modules.nixos.search-tools =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        pkgs.fzf
        pkgs.ripgrep
        pkgs.fd
      ];
    };
}
