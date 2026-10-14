# Приватная часть фичи theme (STR-6): текст файла схемы qt5ct/qt6ct
# `colors/*.conf` — вынесено из theme.nix по превышению мягкого порога
# размера. ПРОВЕРИТЬ (theme.nix, DESIGN_SYSTEM.md Приложение I.6, M7): порядок
# и состав ролей QPalette собран по общеизвестному формату сообщества, не
# сверен с образцами пакета qt6ct.
{ lib }:
{
  mkQtColorScheme =
    {
      neutral,
      semantic,
      accent,
    }:
    let
      # [ColorScheme]: active_colors/inactive_colors/disabled_colors — список
      # из 21 значения QPalette, роли в порядке qt5ct/qt6ct: WindowText,
      # Button, Light, Midlight, Dark, Mid, Text, BrightText, ButtonText,
      # Base, Window, Shadow, Highlight, HighlightedText, Link, LinkVisited,
      # AlternateBase, NoRole, ToolTipBase, ToolTipText, PlaceholderText.
      qtColorList =
        colors:
        lib.concatStringsSep ", " [
          colors.windowText
          colors.button
          colors.light
          colors.midlight
          colors.dark
          colors.mid
          colors.text
          colors.brightText
          colors.buttonText
          colors.base
          colors.window
          colors.shadow
          colors.highlight
          colors.highlightedText
          colors.link
          colors.linkVisited
          colors.alternateBase
          colors.base
          colors.tooltipBase
          colors.tooltipText
          colors.placeholderText
        ];

      active = {
        windowText = neutral.text;
        button = neutral.surface0;
        light = neutral.surface1;
        midlight = neutral.surface0;
        dark = neutral.crust;
        mid = neutral.surface2;
        inherit (neutral) text;
        brightText = neutral.subtext1;
        buttonText = neutral.text;
        inherit (neutral) base;
        window = neutral.base;
        shadow = neutral.crust;
        highlight = accent;
        highlightedText = semantic.on_accent;
        link = semantic.info;
        linkVisited = semantic.special;
        alternateBase = neutral.surface0;
        tooltipBase = neutral.surface0;
        tooltipText = neutral.text;
        placeholderText = neutral.subtext0;
      };
      disabled = active // {
        windowText = neutral.overlay1;
        text = neutral.overlay1;
        buttonText = neutral.overlay1;
        highlight = neutral.overlay0;
        highlightedText = neutral.subtext0;
      };
    in
    ''
      [ColorScheme]
      active_colors=${qtColorList active}
      inactive_colors=${qtColorList active}
      disabled_colors=${qtColorList disabled}
    '';
}
