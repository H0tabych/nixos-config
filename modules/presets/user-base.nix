# Фича: user-base · Слот: — · Домен: presets · Классы: H · Для: всех пользователей
# Контракт: STR-7, ADR-32 — подключается фичей users каждому пользователю
# независимо от capability. shell-zsh и vcs-tools не имеют homeManager-класса
# (HM programs.zsh не используется, A.6; git — системный пакет, см. файл фичи) —
# оболочка и VCS подключаются через N-сторону в пресете base и доступны каждому
# пользователю хоста, что и требует ADR-32.
# Зависимости: —
{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.user-base = {
    imports = [
      hm.dotfiles-link
      hm.user-dirs
    ];
  };
}
