# Фича: office · Слот: — · Домен: presets · Классы: H · Для: пользователей с capability office
# Контракт: STR-7 (пресет — только imports). Мессенджер (R4.5); office-suite,
# mail-calendar, documents — R7.1.
# Зависимости: —
{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.office = {
    imports = [
      hm.communication-telegram
      hm.office-suite-libreoffice
      hm.mail-calendar-thunderbird
      hm.documents-zathura
    ];
  };
}
