# Фича: env-manager-direnv · Слот: env-manager · Домен: shell · Классы: N · Для: всех хостов (base)
# Контракт: слот env-manager (ARCHITECTURE.md §6, контракт ключевых слотов):
# автоактивация проектных окружений с кэшем (R6.1) + слой совместимости для
# динамических бинарников (DEV-7). Хук шелла — целиком в dotfiles (A.6, не два
# хука), поэтому все `enable*Integration` выключены; `programs.direnv.enable`
# нужен только ради системного `/etc/direnv/direnvrc` с nix-direnv (кэш) и
# `DIRENV_CONFIG`, которые читает дотфайловый хук.
# Зависимости: —
_: {
  flake.modules.nixos.env-manager-direnv = { pkgs, ... }: {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableBashIntegration = false;
      enableZshIntegration = false;
      enableFishIntegration = false;
    };
    programs.nix-ld = {
      enable = true;
      # Минимальный документированный список (DEV-7): манилинукс-колёса uv/pip
      # (A.5) ожидают libstdc++ и libz в рантайме.
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
      ];
    };
  };
}
