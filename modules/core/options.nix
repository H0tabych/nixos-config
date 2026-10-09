# Каркас: options · Домен: core
# Опции внешнего уровня (5.3 Архитектуры). Опции my.host.*, my.ai.*, my.tunnel.*
# объявляют *-facts соответствующих доменов, а не этот файл.
{ lib, ... }:
{
  options.my = {
    users = lib.mkOption {
      default = { };
      description = "Реестр пользователей (USER-1).";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            admin = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Права администратора (группа wheel).";
            };
            capabilities = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Список возможностей пользователя (USER-4).";
            };
            dotfiles.source = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Путь к рабочей копии dotfiles пользователя; null — симлинки не создаются (DOT-4).";
            };
          };
        }
      );
    };

    theme.palette = lib.mkOption {
      default = { };
      type = lib.types.attrsOf lib.types.str;
      description = "Палитра из dotfiles theme/palette.toml (DOT-9).";
    };
  };
}
