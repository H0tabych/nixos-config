# Приватная часть владельца: tunnel-xray · Домен: network
# Контракт: NET-7 (исключение маршрута к выходу), VPN-MOD-7. Политика
# маршрутизации режима M2: юнит и скрипты поднятия/снятия правил (STR-6) —
# tunnel-xray.nix растёт за счёт их текста. Секретов нет (SEC-2): адрес
# выхода здесь не упоминается, исключение делается по МЕТКЕ сокета, а не по
# адресу (SEC-4). Импортируется и упоминается только в tunnel-xray.nix (C8).
#
# Зачем этот файл вообще. Проверено на машине 2026-10-14: xray 26.3.27
# создаёт tun-устройство (имя и MTU из settings соблюдает), но системные
# маршруты НЕ настраивает, а неизвестные поля settings игнорирует молча —
# полей вида autoSystemRoutingTable/autoOutboundsInterface в этой версии не
# существует, из-за чего трафик продолжал идти напрямую через физический
# интерфейс. Это ровно тот случай, для которого P.3 предписывает запасной
# путь: «метка сокета на исходящем звене + политика маршрутизации
# (исключение маршрута к выходу, NET-7)». Метку ставит сам конфиг xray
# (sockopt.mark), правила — этот юнит.
#
# Как это не замыкается само на себя. Весь трафик уходит в таблицу туннеля,
# КРОМЕ помеченного меткой xray: правило с меньшим приоритетом отправляет
# помеченное в main, то есть на физический интерфейс. Без этого исключения
# пакеты самого клиента к выходу попадали бы в созданный им же tun — петля
# (критерий M2-2 гейта 7.3).
# Зависимости: —
{ lib, pkgs }:
let
  # Номер таблицы маршрутизации — константа контракта (как порт 443): роль
  # «таблица туннеля», а не параметр хоста. 7777 вне системных таблиц
  # (local=255, main=254, default=253).
  table = 7777;

  # Исключение по метке — ВЫШЕ (меньший номер), иначе собственный трафик
  # клиента уйдёт в туннель и замкнётся.
  priExclude = 100;
  priTunnel = 200;

  # systemd экранирует "-" в имени устройства как \x2d (проверено
  # `systemd-escape --path /sys/subsystem/net/devices/xray-tun0`). Имя юнита
  # собирается из имени интерфейса, а не пишется литералом, чтобы при смене
  # tunInterface ничего не разъехалось.
  deviceUnit =
    iface: "sys-subsystem-net-devices-${lib.replaceStrings [ "-" ] [ "\\x2d" ] iface}.device";
in
{
  inherit table;

  # tunInterface и mark приходят от владельца (константа контракта и
  # my.tunnel.killswitch.mark соответственно) — здесь не дублируются.
  mkRoutesService =
    { tunInterface, mark }:
    let
      ipExe = "${pkgs.iproute2}/bin/ip";
      dev = deviceUnit tunInterface;

      # Снятие вынесено отдельно и вызывается ещё и перед поднятием:
      # `ip rule add` не идемпотентен — повторный запуск накапливал бы дубли.
      teardown = ''
        ${ipExe} rule del priority ${toString priTunnel} 2>/dev/null || true
        ${ipExe} rule del priority ${toString priExclude} 2>/dev/null || true
        ${ipExe} route flush table ${toString table} 2>/dev/null || true
      '';
    in
    {
      description = "Политика маршрутизации туннеля (M2, NET-7)";

      # Юнит привязан к УСТРОЙСТВУ, а не к сервису клиента: устройство
      # появляется асинхронно уже после старта xray, поэтому ExecStartPost у
      # клиента гонялся бы с его созданием. systemd поднимет этот юнит, когда
      # устройство появится, и остановит, когда оно исчезнет.
      bindsTo = [ dev ];
      after = [ dev ];
      wantedBy = [ dev ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        ${teardown}
        ${ipExe} route replace default dev ${tunInterface} table ${toString table}
        ${ipExe} rule add fwmark ${toString mark} lookup main priority ${toString priExclude}
        ${ipExe} rule add lookup ${toString table} priority ${toString priTunnel}
      '';

      preStop = teardown;
    };
}
