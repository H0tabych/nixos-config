# Фича: fonts · Слот: — · Домен: base · Классы: N · Для: всех хостов
# Контракт: — (шрифты системы и метрически совместимые офисные, ARCHITECTURE.md §6).
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
