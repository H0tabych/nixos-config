# Фича: theme · Слот: — · Домен: desktop · Классы: N+H · Для: capability desktop
# Контракт: DESK-6 (палитра, менеджер входа, GTK/Qt, курсор, иконки — один
# владелец). Набор без слота (STR-4) — не сменная реализация, а постоянный
# владелец этой зоны ответственности.
# ПРОВЕРИТЬ: тема SDDM (менеджер входа) не выбрана — N-класс сейчас пуст, здесь
# её место, когда появится решение (DSN-S8, R6.11).
# Палитра — theme/palette.toml входа dotfiles (DOT-9, DSN-TOK-6), читается
# безусловно: закреплённый коммит теперь всегда доступен для загрузки, поэтому
# отложенный пункт R4.3 снят решением ADR-lite (DESIGN_SYSTEM.md, Приложение
# I.3/I.4, DSN-S3). `inputs` приходит бесплатно — flake-parts передаёт его
# каждому модулю через `inherit inputs` в `flake.nix` (тот же приём, что в
# `dotfiles-link.nix`), поэтому `flake.nix` не меняется.
# GTK/Qt/курсор/иконки — не из реестра dotfiles (DOT-1/DOT-3 относятся к
# приложениям реестра), поэтому генераторы HM тут разрешены.
# Курсор и Qt-тема без дублей (DOT-7, Приложение R.1 Д5): `home.pointerCursor`
# и `qt.platformTheme.name` не используются — оба пишут переменные сессии в
# `home.sessionVariables`; `XCURSOR_*`/`QT_QPA_PLATFORMTHEME` — только в
# env-файл UWSM (`session-hyprland.nix`).
# Формат файла схемы qt5ct/qt6ct — приватная часть `_theme-qt-colors.nix`
# (STR-6, ПРОВЕРИТЬ там же).
# Обнаружено на машине 2026-10-15: libadwaita (GTK4) игнорирует
# gtk-application-prefer-dark-theme и gtk-interface-color-scheme из
# settings.ini — тёмную схему он читает только через AdwStyleManager, то есть
# через GSettings-ключ org.gnome.desktop.interface.color-scheme (dconf), не
# через ini-файл. Поэтому `programs.dconf.enable` (N) и `dconf.settings` (H).
# Зависимости: —
{ inputs, lib, ... }:
let
  palette = builtins.fromTOML (builtins.readFile "${inputs.dotfiles}/theme/palette.toml");
  inherit (palette) neutral;
  inherit (palette) semantic;
  variant = palette.variant.${palette.active};

  qtColorScheme = (import ./_theme-qt-colors.nix { inherit lib; }).mkQtColorScheme {
    inherit neutral semantic;
    inherit (variant) accent;
  };
in
{
  flake.modules.nixos.theme =
    { pkgs, ... }:
    {
      programs.dconf.enable = true;

      fonts.packages = [
        pkgs.inter
        pkgs.jetbrains-mono
        pkgs.nerd-fonts.symbols-only
      ];
      fonts.fontconfig = {
        defaultFonts = {
          # APP-2: метрическая совместимость офисных документов — запасные
          # шрифты перед Inter там, где файл требует Arial/Calibri-метрики.
          sansSerif = [
            "Inter"
            "Liberation Sans"
            "Noto Sans"
          ];
          monospace = [ "JetBrains Mono" ];
        };
        hinting.style = "slight";
        subpixel.rgba = "none";
      };
    };

  flake.modules.homeManager.theme =
    { pkgs, config, ... }:
    let
      gtkNamedColors = ''
        @define-color window_bg_color ${neutral.base};
        @define-color view_bg_color ${neutral.surface0};
        @define-color headerbar_bg_color ${neutral.mantle};
        @define-color card_bg_color ${neutral.surface0};
        @define-color accent_bg_color ${variant.accent};
        @define-color accent_fg_color ${semantic.on_accent};
        @define-color accent_color ${variant.accent};
        @define-color destructive_bg_color ${semantic.error};
        @define-color success_color ${semantic.success};
        @define-color warning_color ${semantic.warning};
        @define-color error_color ${semantic.error};
      '';
    in
    {
      gtk = {
        enable = true;
        theme = {
          name = "adw-gtk3-dark";
          package = pkgs.adw-gtk3;
        };
        colorScheme = "dark";
        iconTheme = {
          name = "Papirus-Dark";
          package = pkgs.papirus-icon-theme.override { color = variant.icons; };
        };
        cursorTheme = {
          name = "Bibata-Modern-Ice";
          package = pkgs.bibata-cursors;
          size = 24;
        };
        gtk3.extraCss = gtkNamedColors;
        gtk4.extraCss = gtkNamedColors;
      };

      dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

      # qt.platformTheme не задаётся (см. заголовок), поэтому пакеты qt5ct/
      # qt6ct не попадают в home.packages автоматически (их туда кладёт только
      # platformPackages.qtct в модуле HM) — добавляем явно.
      home.packages = [
        pkgs.libsForQt5.qt5ct
        pkgs.qt6Packages.qt6ct
      ];

      qt = {
        enable = true;
        qt5ctSettings.Appearance = {
          style = "Fusion";
          icon_theme = "Papirus-Dark";
          color_scheme_path = "${config.xdg.configHome}/qt5ct/colors/glass-tide.conf";
          custom_palette = true;
        };
        qt6ctSettings.Appearance = {
          style = "Fusion";
          icon_theme = "Papirus-Dark";
          color_scheme_path = "${config.xdg.configHome}/qt6ct/colors/glass-tide.conf";
          custom_palette = true;
        };
      };

      xdg.configFile = {
        "qt5ct/colors/glass-tide.conf".text = qtColorScheme;
        "qt6ct/colors/glass-tide.conf".text = qtColorScheme;
      };
    };
}
