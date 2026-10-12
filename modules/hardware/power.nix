# Фича: power · Слот: — · Домен: hardware · Классы: N · Для: всех хостов
# Контракт: STO-6 (критический заряд → гибернация). Владеет энергосбережением и
# политикой низкого заряда; политика закрытия крышки — в фиче sleep (ARCH-5: факт
# в одном месте).
# Действие при критическом заряде выбирается по готовности гибернации
# (flake.lib.host.hibernationReady, STO-5): пока смещение swap-файла не задано,
# "Hibernate" был бы пустой кнопкой (L-12) и батарея садилась бы насухо, поэтому
# до R5.1 действует "PowerOff" — единственный вариант upower, не требующий
# гибернации ("HybridSleep" тоже её требует).
# Зависимости: host-facts (my.host.resume.offset) — только чтение значения (ARCH-3).
{ config, ... }:
let
  inherit (config.flake.lib.host) hibernationReady;
in
{
  flake.modules.nixos.power =
    { config, ... }:
    {
      powerManagement = {
        enable = true;
        cpuFreqGovernor = "powersave";
      };

      services.upower = {
        enable = true;
        criticalPowerAction = if hibernationReady config.my.host then "Hibernate" else "PowerOff";
      };
    };
}
