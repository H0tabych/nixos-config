# Фича: development · Слот: — · Домен: presets · Классы: N+H · Для: пользователей с capability development
# Контракт: STR-7, USER-4. Редактор + минимальный lsp-global (R4.4); полный
# lsp-global, databases, api-tools добавятся позже (R6.1+).
# Зависимости: —
{ config, ... }:
let
  n = config.flake.modules.nixos;
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos.development = {
    imports = [ n.editor-neovim ];
  };
  flake.modules.homeManager.development = {
    imports = [
      hm.editor-neovim
      hm.lsp-global
    ];
  };
}
