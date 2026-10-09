# Фича: power · Слот: — · Домен: hardware · Классы: N · Для: всех хостов
# Контракт: STO-6 (критический заряд → гибернация). Владеет энергосбережением и
# политикой низкого заряда; политика закрытия крышки — в фиче sleep (ARCH-5: факт
# в одном месте).
# Зависимости: —
_: {
  flake.modules.nixos.power = _: {
    powerManagement = {
      enable = true;
      cpuFreqGovernor = "powersave";
    };

    services.upower = {
      enable = true;
      criticalPowerAction = "Hibernate";
    };
  };
}
