# Фича: shell-zsh · Слот: shell · Домен: shell · Классы: N · Для: всех хостов (base)
# Контракт: слот shell (ARCHITECTURE.md §6, контракт ключевых слотов): регистрация в
# системе; каталог конфигурации сообщает система (DOT-12), не конфиг — ZDOTDIR через
# `programs.zsh.shellInit` → `/etc/zshenv` (A.6). Путь к oh-my-zsh — в машинный слой
# (DOT-6); содержимое `~/.config/zsh` и хук `env-manager` — целиком в dotfiles (A.6),
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
        "L+ /home/${user}/.config/machine.d/zsh-framework - - - - ${pkgs.writeText "zsh-framework" ''
          # Сгенерировано Nix (shell-zsh, DOT-6) — не редактируйте руками.
          OH_MY_ZSH=${pkgs.oh-my-zsh}/share/oh-my-zsh
        ''}"
      ]) config.my.host.users;
    };
}
