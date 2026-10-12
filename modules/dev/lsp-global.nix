# Фича: lsp-global · Слот: — · Домен: dev · Классы: H · Для: capability development
# Контракт: слот editor → lsp-global (ARCHITECTURE.md §6, контракт слота editor):
# запасные LSP/форматтеры глобально. Минимальный набор под стек CLAUDE.md (python,
# sql, c/c++). `rust-analyzer` НЕ входит — только из проектного окружения (DEV-4).
# Полный список (lua/bash LSP, отладчики, остальные форматтеры) — Приложение A.5,
# ROADMAP R6.1.
# Зависимости: —
_: {
  flake.modules.homeManager.lsp-global = { pkgs, ... }: {
    home.packages = [
      pkgs.nixd
      pkgs.clang-tools
      pkgs.pyright
      pkgs.sqlfluff
    ];
  };
}
