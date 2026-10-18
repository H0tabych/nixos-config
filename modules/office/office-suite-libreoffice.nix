# Фича: office-suite-libreoffice · Слот: office-suite · Домен: office · Классы: H · Для: capability office
# Контракт: слот office-suite (ARCHITECTURE.md §6, Приложение A.3). Словари
# правописания — отдельные пакеты hunspell рядом с пакетом, а не фактами хоста
# (ARCH-5: язык интерфейса/документов не меняется по хосту). Конфиг приложения
# в реестр dotfiles не входит (DOT-2): у LibreOffice нет переносимого текстового
# конфига уровня профиля пользователя, тема — из системного GTK (theme.nix,
# R6.6), а не из палитры напрямую.
# Зависимости: —
_: {
  flake.modules.homeManager.office-suite-libreoffice = { pkgs, ... }: {
    home.packages = [
      pkgs.libreoffice
      pkgs.hunspellDicts.ru_RU
      pkgs.hunspellDicts.en_US
    ];
  };
}
