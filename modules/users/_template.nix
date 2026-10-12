# Шаблон записи пользователя (USER-1, STR-8a, чек-лист 18.4 Архитектуры).
# Скопировать в modules/users/<имя>.nix. Префикс `_` исключает файл из
# автоимпорта (ARCH-2).
#
# Это данные, не логика (D5): только my.users.<имя>. Приватные факты
# пользователя (почта, город) здесь не хранятся — только sops (SEC-2, USER-7).
# Имя пользователя встречается лишь в этом файле, в my.host.users хоста,
# в secrets/users/<имя>.yaml и в .sops.yaml (ARCH-17).
#
# Что ещё нужно сделать для нового пользователя (18.4):
#   1. добавить имя в my.host.users нужных хостов (USER-2)
#   2. ключ age пользователя + правило secrets/users/<имя>.yaml в .sops.yaml
#   3. новая capability — слово в словарь USER-4 и пресет modules/presets/<имя>.nix
_: {
  my.users.CHANGE_ME = {
    admin = false;
    # R2.2: uid и gid задаются явно, чтобы данные из бэкапа не требовали chown.
    uid = null;
    gid = null;
    # USER-4, словарь: desktop development office media gaming ml containers
    capabilities = [ ];
    # DOT-4: путь к рабочей копии dotfiles; null — симлинки ~/.config не создаются.
    dotfiles.source = null;
  };
}
