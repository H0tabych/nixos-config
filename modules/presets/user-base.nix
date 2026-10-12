# Фича: user-base · Слот: — · Домен: presets · Классы: H · Для: всех пользователей
# Контракт: STR-7, ADR-32 — подключается фичей users каждому пользователю
# независимо от capability. shell-zsh не имеет homeManager-класса (HM programs.zsh
# не используется, A.6) — оболочка пользователя подключается через N-сторону в
# пресете base.
# Зависимости: —
{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.user-base = {
    imports = [
      hm.dotfiles-link
      hm.vcs-tools
      hm.user-dirs
    ];
  };
}
