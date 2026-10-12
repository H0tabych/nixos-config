# Фича: theme · Слот: — · Домен: desktop · Классы: N+H · Для: capability desktop
# Контракт: DESK-6 (палитра, менеджер входа, GTK/Qt, курсор, иконки — один
# владелец). Набор без слота (STR-4) — не сменная реализация, а постоянный
# владелец этой зоны ответственности.
# ПРОВЕРИТЬ: тема SDDM (менеджер входа) не выбрана — N-класс сейчас пуст, здесь
# её место, когда появится решение. Чтение theme/palette.toml из входа dotfiles
# (DOT-9) для my.theme.palette сюда не входит (R4.3): безусловное чтение input
# dotfiles форсирует его загрузку независимо от my.users.<имя>.dotfiles.source,
# а закреплённый коммит сейчас недоступен для повторной загрузки — отложено до
# отдельного шага. GTK/Qt/курсор/иконки — не из реестра dotfiles (DOT-1/DOT-3
# относятся к приложениям реестра), поэтому генераторы HM тут разрешены.
# Зависимости: —
_: {
  flake.modules.nixos.theme = { };

  flake.modules.homeManager.theme =
    { pkgs, ... }:
    {
      gtk = {
        enable = true;
        iconTheme = {
          name = "Adwaita";
          package = pkgs.adwaita-icon-theme;
        };
        cursorTheme = {
          name = "Adwaita";
          package = pkgs.adwaita-icon-theme;
        };
      };

      qt = {
        enable = true;
        platformTheme.name = "gtk";
        style.name = "adwaita";
      };
    };
}
