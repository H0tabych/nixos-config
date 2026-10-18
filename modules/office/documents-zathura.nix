# Фича: documents-zathura · Слот: documents · Домен: office · Классы: H · Для: capability office
# Контракт: слот documents (ARCHITECTURE.md §6, Приложение A.3), выбор zathura
# из «zathura или okular» — лёгкий Wayland-native просмотрщик без зависимостей
# KDE/Qt, уже тематизируемый генератором палитры текстовым конфигом (DSN-S9/
# R7.1: DSN-CMP-18). pkgs.zathura — обёртка с плагином poppler по умолчанию
# (pname zathura-with-plugins), отдельный плагин не нужен. Конфиг — реестр
# dotfiles (DOT-2/DOT-3): `zathura/zathurarc`, генерируется theme/gen/gen.py.
# xdg.mimeApps: без явного умолчания PDF открывался в LibreOffice Calc —
# ПРОВЕРЕНО на машине (её .desktop тоже заявляет application/pdf, а без
# mimeapps.list порядок в mimeinfo.cache не гарантирован). Единственный
# текущий потребитель xdg.mimeApps.enable, поэтому владение здесь, не в theme
# (ARCH-5 — появится второй потребитель, перенести в общее место).
# Зависимости: —
_: {
  flake.modules.homeManager.documents-zathura = { pkgs, ... }: {
    home.packages = [ pkgs.zathura ];

    xdg.mimeApps = {
      enable = true;
      defaultApplications."application/pdf" = [ "org.pwmt.zathura.desktop" ];
    };
  };
}
