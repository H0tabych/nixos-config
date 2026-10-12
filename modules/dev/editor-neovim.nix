# Фича: editor-neovim · Слот: editor · Домен: dev · Классы: N+H · Для: capability development
# Контракт: ARCH-9, DEV-1, слот editor (ARCHITECTURE.md §6): пакет и переменная
# EDITOR по умолчанию — только здесь; запасные LSP/форматтеры — отдельная фича
# lsp-global; менеджер плагинов (lazy.nvim) и lock-файл (lazy-lock.json) —
# целиком в dotfiles (DOT-11, A.6).
# Зависимости: —
_: {
  flake.modules.nixos.editor-neovim = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.neovim ];
    environment.variables.EDITOR = "nvim";
  };

  flake.modules.homeManager.editor-neovim = { pkgs, ... }: {
    home.packages = [ pkgs.neovim ];
    home.sessionVariables.EDITOR = "nvim";
  };
}
