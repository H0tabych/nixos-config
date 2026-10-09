# Фича: sleep · Слот: — · Домен: hardware · Классы: N · Для: всех хостов
# Контракт: STO-6 (закрытие крышки → сон с последующей гибернацией, задержка — параметр).
# Устройство resume и смещение swap-файла (my.host.resume.offset, STO-5) задаются в
# storage/swap — там, где swap-файл создаётся (R2.5); здесь их нет осознанно (R2.3:
# «параметры без смещения»).
# Зависимости: —
_: {
  flake.modules.nixos.sleep = _: {
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate";
      HandleLidSwitchExternalPower = "suspend-then-hibernate";
    };

    systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";
  };
}
