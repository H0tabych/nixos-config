# Фича: documents-zathura · Слот: documents · Домен: office · Классы: H · Для: capability office
# Контракт: слот documents (ARCHITECTURE.md §6, Приложение A.3), выбор zathura
# из «zathura или okular» — лёгкий Wayland-native просмотрщик без зависимостей
# KDE/Qt, уже тематизируемый генератором палитры текстовым конфигом (DSN-S9/
# R7.1: DSN-CMP-18). pkgs.zathura — обёртка с плагином poppler по умолчанию
# (pname zathura-with-plugins), отдельный плагин не нужен. Конфиг — реестр
# dotfiles (DOT-2/DOT-3): `zathura/zathurarc`, генерируется theme/gen/gen.py.
# Зависимости: —
_: {
  flake.modules.homeManager.documents-zathura = { pkgs, ... }: {
    home.packages = [ pkgs.zathura ];
  };
}
