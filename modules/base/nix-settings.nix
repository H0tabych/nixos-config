# Фича: nix-settings · Слот: — · Домен: base · Классы: N · Для: всех хостов
# Контракт: ARCH-14 (один стабильный канал + нестабильный точечно), FEAT-4/ARCH-17
# (доверие — через группу, не через имя пользователя), HOST-5 (system.stateVersion —
# параметр хоста).
# Зависимости: host-facts (my.host.stateVersion) — только чтение значения (ARCH-3).
{ inputs, ... }:
{
  flake.modules.nixos.nix-settings =
    { config, ... }:
    {
      # HOST-5: версия состояния системы — параметр хоста, не канала.
      system.stateVersion = config.my.host.stateVersion;

      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        # @wheel, а не имя пользователя — ARCH-17/FEAT-4.
        trusted-users = [
          "root"
          "@wheel"
        ];
        # Явные подписчики кэша (совпадают со значениями по умолчанию `nix show-config`,
        # но зафиксированы явно — критерий шага R2.2).
        substituters = [ "https://cache.nixos.org" ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        ];
        # Оптимизация store — один механизм (не вместе с nix.optimise.automatic).
        auto-optimise-store = true;
      };

      # STO-9, первая половина: GC по расписанию. options намеренно НЕ задаются —
      # до PNR-3 поколения не удаляются (W5, R5.3). `--delete-older-than` по
      # man nix-collect-garbage(1) «deletes all generations of profiles older
      # than the specified amount» и эквивалентен nix-env --delete-generations,
      # то есть снёс бы и поколения системы — единственный способ откатиться
      # (OPS-5, A11). Без options команда вырождается в nix-store --gc: удаляет
      # только недостижимые пути, поколения остаются.
      # Освобождается меньше места — это принятая плата; порог тревоги по
      # свободному месту и бюджет ёмкости ведутся в docs/runbook.md (STO-11).
      # Вторая половина STO-9 — лимит записей загрузчика — в storage/layout.
      nix.gc = {
        automatic = true;
        dates = "weekly";
      };

      nixpkgs.config.allowUnfree = true;

      # Нестабильный канал — точечно, через overlay с причиной (ARCH-14): пакеты без
      # релиза в стабильной ветке доступны как pkgs.unstable.<имя>.
      nixpkgs.overlays = [
        (_final: prev: {
          unstable = import inputs.nixpkgs-unstable {
            inherit (prev) system;
            config.allowUnfree = true;
          };
        })
      ];
    };
}
