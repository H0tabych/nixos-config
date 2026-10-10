# Фича: development · Слот: — · Домен: presets · Классы: N+H · Для: пользователей с capability development
# Контракт: STR-7, USER-4. Минимальный состав — редактор (R2.6); lsp-global,
# databases, api-tools добавятся позже.
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
    imports = [ hm.editor-neovim ];
  };
}
