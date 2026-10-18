# Фича: compat-layer-proton-ge · Слот: compat-layer · Домен: gaming · Классы: N · Для: capability gaming
# Контракт: A.3 (слот compat-layer → Proton-GE). Вкладчик в Steam, не владелец
# (ADR-34): programs.steam.extraCompatPackages — опция-интерфейс владельца
# game-platform-steam, зависимость выражена assertion'ом, а не импортом
# фичи (ARCH-3).
# Зависимости: game-platform-steam (programs.steam.enable) — только assertion.
_: {
  flake.modules.nixos.compat-layer-proton-ge =
    { config, pkgs, ... }:
    {
      assertions = [
        {
          assertion = config.programs.steam.enable;
          message = "фича compat-layer-proton-ge требует game-platform-steam (programs.steam.enable)";
        }
      ];

      programs.steam.extraCompatPackages = [ pkgs.proton-ge-bin ];
    };
}
