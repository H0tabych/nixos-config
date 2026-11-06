# Фича: torrent-transmission · Слот: torrent · Домен: media · Классы: N+H · Для: capability media
# Контракт: слот torrent (ARCHITECTURE.md §6, Приложение A.3); VPN-A6, VPN-INT-3,
# ADR-43 — торрент-трафик идёт напрямую, мимо выхода, в M1 и в M2.
#
# Почему служба, а не оконный клиент. В M2 «напрямую» значит «с меткой туннеля» (kill
# switch и правило `not fwmark` пропускают её), а метку ставит политика туннеля по
# **uid** системного пользователя (my.tunnel.bypass.users, ADR-43). Процесс сессии идёт
# под uid самого пользователя, отделить его от остальных его программ нельзя;
# признак по cgroup не годится (путь не существует при загрузке правил, а после
# перезапуска юнита меняется id каталога). Поэтому Transmission — системный демон со
# своим пользователем `transmission`, а в сессии — `transmission-remote-gtk`.
# Протокол BitTorrent по-прежнему направляется `direct` в политике клиента туннеля
# (VPN-RTE-2), но шифрованный им не определяется — надёжен только обход по uid.
# В M1 клиент прокси-переменных не читает (у демона их нет): раздача и так идёт
# напрямую, обходу делать нечего.
#
# Доступ. RPC — только loopback (rpc-bind-address по умолчанию), **без пароля и без
# секретов**: как у инференса (AI-INF-1), принято осознанно (ADR-43). Через RPC можно
# добавить торрент и сменить настройки, но не выполнить код: скрипт по завершению
# выключен, а служба заперта (RootDirectory, ProtectSystem, запись только в свои каталоги).
# Каталоги — на томе вне снимков и бэкапа (/var/lib/nosnapshot, STO-1, AI-INF-8
# по аналогии): загрузки не должны попадать в снимки корня. Доступ пользователям
# capability media — членство в группе transmission, umask 002.
#
# my.net.bypass.users объявляет net-facts (пресет base): хост с media без tunnel обязан
# собираться, а my.tunnel.* там нет (причина — в шапке net-facts).
# Конфиг клиента (профиль подключения) — в репозитории dotfiles (ARCH-15, DOT-3).
# Зависимости: net-facts (my.net.bypass.users),
# layout (том /var/lib/nosnapshot), my.users.<имя>.capabilities — через config (ARCH-3).
{ config, lib, ... }:
let
  outer = config;
  usersWithCap = lib.attrNames (
    lib.filterAttrs (_: u: lib.elem "media" u.capabilities) outer.my.users
  );
in
{
  flake.modules.nixos.torrent-transmission =
    { config, lib, ... }:
    let
      cfg = config.services.transmission;
      allowedUsers = lib.intersectLists config.my.host.users usersWithCap;
      root = "/var/lib/nosnapshot/torrents";
    in
    {
      services.transmission = {
        enable = true;
        # install -d в transmission-setup создаёт каталоги с этими правами; группа
        # transmission — пользователи capability media (ниже).
        downloadDirPermissions = "0770";
        settings = {
          download-dir = "${root}/complete";
          incomplete-dir = "${root}/incomplete";
          umask = "002";
        };
      };

      # Корень каталога данных — до transmission-setup, который создаёт подкаталоги.
      systemd.tmpfiles.rules = [ "d ${root} 0750 ${cfg.user} ${cfg.group} -" ];

      users.users = lib.genAttrs allowedUsers (_: {
        extraGroups = [ cfg.group ];
      });

      # ADR-43: прямой путь для службы по её uid; читает политика туннеля, если она есть
      # (в M1 ничего не меняет: демон прокси-переменных не читает).
      my.net.bypass.users = [ cfg.user ];
    };

  flake.modules.homeManager.torrent-transmission =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.transmission-remote-gtk ];
    };
}
