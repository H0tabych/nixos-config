# Фича: btop · Слот: — · Домен: shell · Классы: H · Для: capability desktop
# Контракт: DEV-1 (VCS и утилиты — общий минимум), ARCHITECTURE.md §6 shell:
# пакет; конфиг — dotfiles (A.4), цвета и theme_background=false — из
# генератора палитры (DESIGN_SYSTEM.md П.3.5). HM-модуль без
# programs.btop — его в nixpkgs нет, пакет и так самодостаточен.
# Зависимости: —
_: {
  flake.modules.homeManager.btop = { pkgs, ... }: {
    home.packages = [ pkgs.btop ];
  };
}
