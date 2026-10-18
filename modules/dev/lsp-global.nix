# Фича: lsp-global · Слот: — · Домен: dev · Классы: H · Для: capability development
# Контракт: слот editor → lsp-global (ARCHITECTURE.md §6, контракт слота editor):
# запасные LSP, форматтеры и отладчики глобально (DEV-1, DEV-5), полный состав —
# Приложение A.5. `rust-analyzer` НЕ входит — только из проектного окружения (DEV-4).
# R6.12, ПРОВЕРЕНО headless-прогоном Neovim: nvim-treesitter компилирует
# парсеры (`:TSUpdate`) вызовом `cc`/`gcc` в PATH — без компилятора падает с
# «No C compiler found»; редактору он нужен независимо от проектного
# тулчейна (DEV-2 про тулчейны относится к сборке проекта, не к самому
# редактору), поэтому `gcc` — здесь, а не в шаблонах cpp/rust.
# branch = "main" nvim-treesitter (ПРОВЕРЕНО живьём на Neovim 0.12: branch
# "master" несовместима с ядром 0.12+) вызывает внешний бинарь `tree-sitter
# build`/`generate`, а не только cc — добавлен пакет tree-sitter рядом с gcc.
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
      # компиляция грамматик treesitter в редакторе (R6.12)
      pkgs.gcc
      pkgs.tree-sitter
    ];
  };
}
