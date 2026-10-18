# Фича: fonts · Слот: — · Домен: base · Классы: N · Для: всех хостов
# Контракт: — (шрифты системы и метрически совместимые офисные, ARCHITECTURE.md §6).
# R7.1 (A9): добавлены carlito/caladea — без них современные .docx/.pptx с
# Calibri/Cambria (умолчания MS Office с 2007) подменялись бы шрифтом в LibreOffice.
# Зависимости: —
_: {
  flake.modules.nixos.fonts =
    { pkgs, ... }:
    {
      fonts.packages = with pkgs; [
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
        # Метрически совместимы с Arial/Times New Roman/Courier New — документы MS Office.
        liberation_ttf
        dejavu_fonts
        # Метрически совместимы с Calibri/Cambria — документы MS Office ≥ 2007.
        carlito
        caladea
      ];

      fonts.fontconfig.defaultFonts = {
        serif = [
          "Liberation Serif"
          "Noto Serif"
        ];
        sansSerif = [
          "Liberation Sans"
          "Noto Sans"
        ];
        monospace = [
          "Liberation Mono"
          "Noto Sans Mono"
        ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
}
