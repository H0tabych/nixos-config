# Фича: user-dirs · Слот: — · Домен: shell · Классы: H · Для: всех пользователей
# Контракт: — (стандартные каталоги XDG — Desktop/Documents/Downloads/…,
# ARCHITECTURE.md §6 — shell). Имена — латиницей (home-manager default) и не
# зависят от локали; user-dirs.conf запрещает xdg-user-dirs-update переименовать
# их при логине под локаль системы.
# Зависимости: —
_: {
  flake.modules.homeManager.user-dirs = _: {
    xdg.userDirs = {
      enable = true;
      createDirectories = true;
    };
  };
}
