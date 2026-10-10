# Фича: user-base · Слот: — · Домен: presets · Классы: H · Для: всех пользователей
# Контракт: STR-7, ADR-32 — подключается фичей users каждому пользователю
# независимо от capability. dotfiles-link, shell-zsh, vcs-tools,
# env-manager-direnv появятся в R4.2/R4.4; до тех пор состав пуст.
# Зависимости: —
_: {
  flake.modules.homeManager.user-base = {
    imports = [ ];
  };
}
