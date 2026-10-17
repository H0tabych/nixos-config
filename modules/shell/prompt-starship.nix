# Фича: prompt-starship · Слот: prompt · Домен: shell · Классы: N+H · Для: всех хостов (base) и всех пользователей (user-base)
# Контракт: слот prompt (ARCHITECTURE.md §6, DSN-CMP-12 DESIGN_SYSTEM.md): пакет;
# путь к конфигу задаёт система через STARSHIP_CONFIG (DOT-12), по образцу
# ZDOTDIR в shell-zsh.nix; содержимое starship.toml и инициализация промпта
# (`starship init zsh`, простой промпт в tty при $TERM=linux, DSN-CMP-12) —
# целиком в dotfiles (DOT-3). STARSHIP_LOG=error — таймаут VCS-статуса
# (DSN-CMP-12: ≤ 50 мс, сегмент отбрасывается) в норме и ожидаем на больших
# деревьях; подавляет штатный WARN starship об этом, не трогая сам таймаут
# (ПРОВЕРЕНО на машине, R6.9).
# Зависимости: shell-zsh (programs.zsh.enable) — assertion, не импорт (ARCH-3).
_: {
  flake.modules.nixos.prompt-starship =
    { config, ... }:
    {
      assertions = [
        {
          assertion = config.programs.zsh.enable;
          message = "фича prompt-starship требует programs.zsh.enable (фича shell-zsh) в составе хоста";
        }
      ];

      programs.zsh.shellInit = ''
        export STARSHIP_CONFIG="$HOME/.config/starship/starship.toml"
        export STARSHIP_LOG=error
      '';
    };

  flake.modules.homeManager.prompt-starship = { pkgs, ... }: { home.packages = [ pkgs.starship ]; };
}
