# Фича: shell-zsh · Слот: shell · Домен: shell · Классы: N · Для: всех хостов (base)
# Контракт: слот shell (ARCHITECTURE.md §6, контракт ключевых слотов): регистрация в
# системе; каталог конфигурации сообщает система (DOT-12), не конфиг — ZDOTDIR через
# `programs.zsh.shellInit` → `/etc/zshenv` (A.6). Пути к oh-my-zsh и плагинам — в
# машинный слой, файл `machine.d/zsh-env` (DOT-6, REGISTRY.md dotfiles, A.6 «zsh /
# редактор»): oh-my-zsh — только для своих плагинов (DESIGN_SYSTEM.md П.3.5);
# zsh-autosuggestions/zsh-syntax-highlighting/zsh-completions/
# zsh-history-substring-search — сторонние, не входят в сборку oh-my-zsh, поэтому
# отдельные переменные (dotfiles подключает их сам, минуя механизм ZSH_CUSTOM —
# он требует запись в путь нижезависимый от /nix/store). Подсветка синтаксиса — по
# требованию самого плагина — должна быть подключена последней в .zshrc (dotfiles).
# Содержимое `~/.config/zsh` и хук `env-manager` — целиком в dotfiles (A.6),
# симлинк создаёт `dotfiles-link` по каталогу dotfiles. HM `programs.zsh` не
# используется (A.6) — у фичи нет homeManager-класса.
# Зависимости: host-facts (my.host.users) — адресаты машинного слоя.
_: {
  flake.modules.nixos.shell-zsh =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      programs.zsh = {
        enable = true;
        shellInit = ''
          export ZDOTDIR="$HOME/.config/zsh"
        '';
      };
      users.defaultUserShell = pkgs.zsh;

      systemd.tmpfiles.rules = lib.concatMap (user: [
        "L+ /home/${user}/.config/machine.d/zsh-env - - - - ${pkgs.writeText "zsh-env" ''
          # Сгенерировано Nix (shell-zsh, DOT-6) — не редактируйте руками.
          export OH_MY_ZSH=${pkgs.oh-my-zsh}/share/oh-my-zsh
          export ZSH_AUTOSUGGESTIONS=${pkgs.zsh-autosuggestions}/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
          export ZSH_SYNTAX_HIGHLIGHTING=${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
          export ZSH_COMPLETIONS=${pkgs.zsh-completions}/share/zsh/site-functions
          export ZSH_HISTORY_SUBSTRING_SEARCH=${pkgs.zsh-history-substring-search}/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
        ''}"
      ]) config.my.host.users;
    };
}
