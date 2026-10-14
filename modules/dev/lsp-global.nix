# Фича: lsp-global · Слот: — · Домен: dev · Классы: H · Для: capability development
# Контракт: слот editor → lsp-global (ARCHITECTURE.md §6, контракт слота editor):
# запасные LSP, форматтеры и отладчики глобально (DEV-1, DEV-5), полный состав —
# Приложение A.5. `rust-analyzer` НЕ входит — только из проектного окружения (DEV-4).
# Зависимости: —
_: {
  flake.modules.homeManager.lsp-global = { pkgs, ... }: {
    home.packages = [
      # LSP
      pkgs.nixd
      pkgs.clang-tools
      pkgs.pyright
      pkgs.ruff
      pkgs.lua-language-server
      pkgs.bash-language-server
      pkgs.sqlfluff
      # форматтеры (DEV-8: тот же nixfmt, что и в core/treefmt.nix)
      pkgs.nixfmt
      pkgs.stylua
      pkgs.shfmt
      # отладка (DEV-5)
      pkgs.python3Packages.debugpy
      pkgs.lldb
    ];
  };
}
