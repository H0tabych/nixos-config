# Запись пользователя: sgm · Домен: users · Для: sgm
# Контракт: STR-8a, USER-1 (внешний scope). Единственное место в modules/, где
# встречается имя пользователя (ARCH-17). Приватные факты — только в sops (SEC-2).
# Зависимости: —
_: {
  my.users.sgm = {
    admin = true;
    uid = 1000;
    gid = 1000;
    capabilities = [
      "desktop"
      "development"
      "office"
      "media"
      "gaming"
      "ml"
    ];
    # Рабочая копия dotfiles (R4.6, DOT-4); включает симлинки ~/.config/<app>.
    dotfiles.source = "/home/sgm/.dotfiles";
  };
}
