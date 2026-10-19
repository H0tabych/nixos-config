# Фича: development · Слот: — · Домен: presets · Классы: N+H · Для: пользователей с capability development
# Контракт: STR-7, USER-4. Редактор + полный lsp-global (R6.1) + databases
# (R6.3) + pycharm (необязательная IDE, DEV-9/AI-CMP-8); api-tools —
# опционально, пока не введена (не выдумываем состав без записи в
# ARCHITECTURE.md A.3).
# editor-neovim — только N-класс (пакет и EDITOR системные, см. файл фичи),
# поэтому в homeManager-части его нет.
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
      hm.lsp-global
      hm.databases
      hm.pycharm
    ];
  };
}
