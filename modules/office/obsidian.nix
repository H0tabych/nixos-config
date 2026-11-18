# Фича: obsidian · Слот: — · Домен: office · Классы: H · Для: capability office
# Контракт: DOT-2 — приложение вне реестра dotfiles: настройки Obsidian хранит внутри
# самого хранилища (`<хранилище>/.obsidian`), поэтому фича ограничена установкой пакета.
# Хранилище — `~/Documents/Obsidian` (создаёт сам Obsidian при первом запуске). Тема Glass Tide —
# CSS-сниппет из `theme/export/` dotfiles, подключается вручную (DESIGN_SYSTEM.md, P.3.7).
# Лицензия unfree — разрешена глобально (nix-settings: allowUnfree).
# Зависимости: —
_: {
  flake.modules.homeManager.obsidian = { pkgs, ... }: {
    home.packages = [ pkgs.obsidian ];
  };
}
