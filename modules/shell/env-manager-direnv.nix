# Фича: env-manager-direnv · Слот: env-manager · Домен: shell · Классы: N · Для: всех хостов (base)
# Контракт: слот env-manager (ARCHITECTURE.md §6, контракт ключевых слотов):
# автоактивация проектных окружений с кэшем — полная автоактивация и кэш добавятся
# в R6.1; слой совместимости для динамических бинарников (nix-ld) — здесь.
# `programs.direnv.enable` не используется: он сам вписывает хук в шелл, а хук
# целиком в dotfiles, чтобы не было двух хуков (A.6) — здесь только пакеты.
# Зависимости: —
_: {
  flake.modules.nixos.env-manager-direnv = { pkgs, ... }: {
    environment.systemPackages = [
      pkgs.direnv
      pkgs.nix-direnv
    ];
    programs.nix-ld.enable = true;
  };
}
