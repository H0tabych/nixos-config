# Фича: editor-neovim · Слот: editor · Домен: dev · Классы: N · Для: capability development
# Контракт: ARCH-9, DEV-1, DEV-9, слот editor (ARCHITECTURE.md §6): пакет и
# переменная EDITOR по умолчанию — только здесь; запасные LSP/форматтеры —
# отдельная фича lsp-global; менеджер плагинов (lazy.nvim) и lock-файл
# (lazy-lock.json) — целиком в dotfiles (DOT-11, A.6).
# Только N-класс. Раньше были оба, и это давало два определения одного факта
# (ARCH-5, L-8): пакет в environment.systemPackages и в home.packages, EDITOR в
# environment.variables и в home.sessionVariables. Причём HM-определения были
# мёртвыми: home.sessionVariables доставляется через hm-session-vars.sh, а его
# никто не подключает — HM-модули programs.zsh/programs.bash не используются
# (A.6), /etc/profile и /etc/zshenv читают только /etc/set-environment.
# Переменная и бинарник должны быть в одной области видимости (DEV-9: не
# ссылаться на отсутствующий в PATH бинарник), поэтому оба — системные;
# глобальный редактор предусмотрен DEV-1.
# Зависимости: —
_: {
  flake.modules.nixos.editor-neovim =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.neovim ];
      environment.variables.EDITOR = "nvim";
    };
}
