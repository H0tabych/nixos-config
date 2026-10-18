# Фича: display-manager-sddm · Слот: display-manager · Домен: desktop · Классы: N · Для: capability desktop
# Контракт: слот display-manager (ARCHITECTURE.md §6, контракт ключевых слотов).
# Предлагает сессии установленных session-<р> (сейчас — session-hyprland).
# Тема — sddm-astronaut (DSN-S8, DESIGN_SYSTEM.md P.3.4), цвета и обои из
# палитры (DESK-6). `postInstall` пакета sddm-astronaut не выполняется — его
# installPhase не вызывает `runHook postInstall` (проверено тестовой сборкой с
# маркер-файлом); копирование обоев сделано через `postFixup`, который
# стандартная fixupPhase вызывает всегда. `HaveFormBackground = "true"` нужен
# вместе с `PartialBlur`/`FormBackgroundColor`, иначе панель формы невидима
# (Main.qml темы: `visible` поля формы зависит от `HaveFormBackground`).
# Зависимости: —
{ inputs, ... }:
let
  palette = builtins.fromTOML (builtins.readFile "${inputs.dotfiles}/theme/palette.toml");
  inherit (palette) neutral semantic;
  variant = palette.variant.${palette.active};

  wallpaperFile = "${inputs.dotfiles}/theme/wallpapers/${variant.wallpaper.file}";
  wallpaperName = "glass-tide.jpg";

  themeConfig = {
    Font = palette.font.ui;

    HeaderTextColor = neutral.text;
    DateTextColor = neutral.subtext0;
    TimeTextColor = neutral.text;

    Background = wallpaperName;
    BackgroundColor = neutral.crust;
    DimBackgroundColor = neutral.crust;
    DimBackground = "0.35";

    HaveFormBackground = "true";
    PartialBlur = "true";
    FormBackgroundColor = neutral.surface0;

    LoginFieldBackgroundColor = neutral.surface0;
    PasswordFieldBackgroundColor = neutral.surface0;
    LoginFieldTextColor = neutral.text;
    PasswordFieldTextColor = neutral.text;
    UserIconColor = neutral.subtext0;
    PasswordIconColor = neutral.subtext0;
    PlaceholderTextColor = neutral.subtext0;

    WarningColor = semantic.warning;

    LoginButtonTextColor = semantic.on_accent;
    LoginButtonBackgroundColor = variant.accent;
    SystemButtonsIconsColor = neutral.subtext0;
    SessionButtonTextColor = neutral.subtext0;
    VirtualKeyboardButtonTextColor = neutral.subtext0;

    DropdownTextColor = neutral.text;
    DropdownSelectedBackgroundColor = variant.accent;
    DropdownBackgroundColor = neutral.surface0;

    HighlightTextColor = semantic.on_accent;
    HighlightBackgroundColor = variant.accent;
    HighlightBorderColor = variant.accent;

    HoverUserIconColor = variant.accent;
    HoverPasswordIconColor = variant.accent;
    HoverSystemButtonsIconsColor = variant.accent;
    HoverSessionButtonTextColor = variant.accent;
    HoverVirtualKeyboardButtonTextColor = variant.accent;
  };
in
{
  flake.modules.nixos.display-manager-sddm =
    { pkgs, ... }:
    let
      themed =
        (pkgs.sddm-astronaut.override {
          embeddedTheme = "astronaut";
          inherit themeConfig;
        }).overrideAttrs
          (old: {
            postFixup = (old.postFixup or "") + ''
              cp ${wallpaperFile} $out/share/sddm/themes/sddm-astronaut-theme/Backgrounds/${wallpaperName}
            '';
          });
    in
    {
      services.displayManager.sddm = {
        enable = true;
        wayland.enable = true;
        theme = "${themed}/share/sddm/themes/sddm-astronaut-theme";
        # Main.qml темы импортирует QtMultimedia (видео-фон); без модуля в
        # QML2_IMPORT_PATH greeter откатывается на встроенную тему (проверено
        # по журналу: "module QtMultimedia is not installed" → "Fallback to
        # embedded theme").
        extraPackages = [ pkgs.qt6.qtmultimedia ];
      };
    };
}
