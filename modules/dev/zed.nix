# Фича: zed · Слот: — · Домен: dev · Классы: H · Для: capability development
# Контракт: DEV-9, AI-CMP-8, DOT-2 — необязательный GUI-редактор. Nix даёт только пакет;
# конфиг (`settings.json`, `keymap.json`) и тема Glass Tide — каталог `zed/` реестра dotfiles
# (симлинк ~/.config/zed делает dotfiles-link). Языковые серверы берёт из PATH (lsp-global),
# автообновление и телеметрия выключены в settings.json.
# Зависимости: —
_: {
  flake.modules.homeManager.zed = { pkgs, ... }: {
    home.packages = [ pkgs.zed-editor ];
  };
}
