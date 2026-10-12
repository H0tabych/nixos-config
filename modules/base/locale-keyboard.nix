# Фича: locale-keyboard · Слот: — · Домен: base · Классы: N · Для: всех хостов
# Контракт: DESK-7 (единственный источник раскладок; рабочий стол получает их через
# машинный слой). Значения — по ARCHITECTURE.md §7 (laptop_spec).
# Зависимости: host-facts (my.host.keyboardLayout) — только чтение значения (ARCH-3).
_: {
  flake.modules.nixos.locale-keyboard =
    { config, lib, ... }:
    let
      # DESK-7: раскладка — один источник (my.host.keyboardLayout). Консоль
      # понимает только одну раскладку, поэтому берём первую из списка xkb,
      # а не отдельную константу — иначе два источника разошлись бы (L-8).
      consoleLayout = lib.head (lib.splitString "," config.my.host.keyboardLayout);
    in
    {
      time.timeZone = "Europe/Moscow";

      i18n.defaultLocale = "en_US.UTF-8";
      i18n.extraLocaleSettings = {
        LC_ADDRESS = "ru_RU.UTF-8";
        LC_IDENTIFICATION = "ru_RU.UTF-8";
        LC_MEASUREMENT = "ru_RU.UTF-8";
        LC_MONETARY = "ru_RU.UTF-8";
        LC_NAME = "ru_RU.UTF-8";
        LC_NUMERIC = "ru_RU.UTF-8";
        LC_PAPER = "ru_RU.UTF-8";
        LC_TELEPHONE = "ru_RU.UTF-8";
        LC_TIME = "ru_RU.UTF-8";
      };

      console.keyMap = consoleLayout;

      services.xserver.xkb = {
        layout = config.my.host.keyboardLayout;
        options = "grp:alt_shift_toggle";
      };
    };
}
