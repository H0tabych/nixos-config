# Фича: sleep · Слот: — · Домен: hardware · Классы: N · Для: всех хостов
# Контракт: STO-6 (закрытие крышки → сон с последующей гибернацией, задержка — параметр).
# Устройство resume и смещение swap-файла (my.host.resume.offset, STO-5) задаются в
# storage/swap — там, где swap-файл создаётся (R5.1); здесь они только читаются.
# Политика крышки выбирается по готовности гибернации
# (flake.lib.host.hibernationReady): без смещения swap-файла
# "suspend-then-hibernate" не смог бы перейти в гибернацию (L-12), поэтому до R5.1
# действует обычный "suspend". HibernateDelaySec задаётся всегда — это параметр
# политики (STO-6), systemd применяет его только к suspend-then-hibernate.
# Зависимости: host-facts (my.host.resume.offset) — только чтение значения (ARCH-3).
{ config, ... }:
let
  inherit (config.flake.lib.host) hibernationReady;
in
{
  flake.modules.nixos.sleep =
    { config, ... }:
    let
      lidAction = if hibernationReady config.my.host then "suspend-then-hibernate" else "suspend";
    in
    {
      services.logind.settings.Login = {
        HandleLidSwitch = lidAction;
        HandleLidSwitchExternalPower = lidAction;
      };

      systemd.sleep.settings.Sleep.HibernateDelaySec = "30min";
    };
}
