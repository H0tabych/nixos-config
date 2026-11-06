# Приватная часть владельца: tunnel-xray · Домен: network
# Контракт: NET-7, VPN-MOD-12, VPN-KS-10, ADR-41. Сетевая обвязка режима M2 со
# стороны ОС: политика маршрутизации, адрес интерфейса, сохранение метки клиента
# (STR-6). Секретов нет (SEC-2): адрес выхода здесь не упоминается, исключение
# делается по МЕТКЕ сокета, а не по адресу (SEC-4). Импортируется и упоминается
# только в tunnel-xray.nix (C8).
#
# Схема та же, что у wg-quick:
#   - правило suppress_prefixlength: конкретные маршруты main (LAN, docker0,
#     корпоративный tun0) работают как обычно, не уходя в туннель (VPN-RTE-4);
#   - правило `not fwmark`: остальное идёт в таблицу туннеля, а сокеты самого
#     клиента в неё не попадают никогда, даже когда в main нет маршрута, поэтому
#     петли нет (M2-2). Они следуют main, так что смена сети не требует ни
#     отслеживания интерфейсов, ни перезапуска клиента (M2-3, L-16);
#   - unreachable в таблице туннеля: пока устройства нет, приложения получают
#     отказ сразу, и до физического интерфейса пакеты не доходят (VPN-KS-3, VPN-A8).
#
#   - обход (VPN-INT-3, ADR-43): `uidrange <uid> lookup main` раньше обоих — маршрут
#     и **адрес источника** выбираются при connect(), когда пакет ещё не помечен;
#     иначе сокет получил бы адрес туннеля, и потом пакет с чужим адресом ушёл бы
#     на физический интерфейс. Метка (mkMarksTable) нужна ниже для пропуска kill switch
#     и обратного пути ответов, а не для выбора маршрута.
#
# Правила и unreachable ставит юнит до подъёма сети: они не зависят от клиента.
# Адрес и маршрут через устройство ставит ExecStartPost клиента, а исчезают они
# вместе с устройством. Настройка из самого Xray (gateway, autoSystemRoutingTable)
# не используется: маршрут там ставится в main, и его нельзя совместить со строгим
# rpfilter, а конфиг перестал бы быть независимым от версии ядра туннеля.
# Зависимости: —
{ pkgs, lib }:
let
  # Номер таблицы маршрутизации — константа контракта (как порт 443): роль
  # «таблица туннеля», а не параметр хоста. 7777 вне системных таблиц
  # (local=255, main=254, default=253).
  table = toString 7777;

  # Оба правила перед `lookup main` (32766).
  priMain = toString 32000;
  priTunnel = toString 32001;
  # Обход (ADR-43): правило по uid раньше обоих.
  priBypass = toString 31999;

  ip = "${pkgs.iproute2}/bin/ip -4";

  routeViaLink = name: "${ip} route replace default dev ${name} metric 1 table ${table}";
in
{
  # interface и mark приходят от владельца (my.tunnel.interface и
  # my.tunnel.killswitch.mark) — здесь не дублируются.
  mkRoutesService =
    {
      interface,
      mark,
      bypassUids ? [ ],
    }:
    let
      # Снятие вынесено отдельно и вызывается ещё и перед поднятием:
      # `ip rule add` не идемпотентен — повторный запуск накапливал бы дубли.
      teardown = ''
        while ${ip} rule del priority ${priBypass} 2>/dev/null; do :; done
        ${ip} rule del priority ${priTunnel} 2>/dev/null || true
        ${ip} rule del priority ${priMain} 2>/dev/null || true
        ${ip} route flush table ${table} 2>/dev/null || true
      '';
    in
    {
      description = "Политика маршрутизации туннеля (M2, VPN-MOD-12)";

      # Порядок как у nftables.service: до подъёма сети, иначе есть окно, когда
      # трафик идёт по main, и его держит только kill switch.
      unitConfig.DefaultDependencies = false;
      after = [ "sysinit.target" ];
      before = [
        "network-pre.target"
        "shutdown.target"
      ];
      wants = [ "network-pre.target" ];
      conflicts = [ "shutdown.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      # Маршрут через устройство повторяется здесь потому, что при активации этот
      # юнит может перезапуститься без клиента, а teardown сбрасывает таблицу.
      script = ''
        ${teardown}
        ${ip} route replace unreachable default metric 4294967295 table ${table}
        ${routeViaLink interface.name} 2>/dev/null || true
        ${ip} rule add lookup main suppress_prefixlength 0 priority ${priMain}
        ${ip} rule add not fwmark ${toString mark} lookup ${table} priority ${priTunnel}
      ''
      + lib.concatMapStrings (uid: ''
        ${ip} rule add uidrange ${toString uid}-${toString uid} lookup main priority ${priBypass}
      '') bypassUids;

      preStop = teardown;
    };

  # Устройство появляется после старта процесса, а поднимается ещё позже: маршрут
  # через опущенное устройство ядро отклоняет. Поэтому ожидание с ограничением, а
  # не единичная попытка. multicast off: иначе резолвер отправляет в туннель запросы
  # LLMNR и mDNS, а клиент выпускает их напрямую.
  mkLinkUp =
    { interface }:
    pkgs.writeShellScript "tunnel-link-up" ''
      for _ in {1..100}; do
        if ${ip} link set dev ${interface.name} multicast off 2>/dev/null \
          && ${ip} addr replace ${interface.address} peer ${interface.dnsAddress} dev ${interface.name} 2>/dev/null \
          && ${routeViaLink interface.name} 2>/dev/null; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done
      echo "tunnel-link-up: устройство ${interface.name} не поднялось за 10 с" >&2
      exit 1
    '';

  # Ответ выхода приходит с физического интерфейса без метки. rpfilter файрвола
  # проверял бы его по таблице туннеля и отбросил: обратный маршрут там через
  # устройство туннеля, а не через интерфейс прихода. Метка сохраняется в conntrack
  # и восстанавливается на входе раньше rpfilter (его приоритет — mangle + 10),
  # поэтому строгую проверку ослаблять не нужно.
  #
  # Обход (VPN-INT-3, ADR-43). Трафик пользователей из my.net.bypass.users получает
  # ту же метку, что и сокеты клиента: роль метки — «прямой путь» (пропуск kill switch,
  # VPN-KS-2, и возврат ответов через conntrack), а не «клиент». Маршрут им выбирает
  # правило по uid (mkRoutesService): выбор по метке в цепочке output поздно — адрес
  # источника уже взят у туннеля при connect(). Признак здесь тоже числовой uid: он не
  # зависит от жизни юнита и грузится в любой момент (cgroup — нет, причина в шапке
  # net-facts). Приоритет mangle раньше kill switch (filter): к его правилам метка уже
  # стоит. DNS и DoT (порты 53, 853) не помечаются: иначе обходной пользователь слал бы
  # их провайдеру, а KS-5 обязан резать их ДО общих разрешений (получит отказ).
  mkMarksTable =
    {
      mark,
      bypassUids ? [ ],
    }:
    {
      family = "inet";
      content = ''
        chain save {
          type filter hook postrouting priority mangle;
          meta mark ${toString mark} ct mark set meta mark
        }

        chain restore {
          type filter hook prerouting priority mangle;
          ct mark ${toString mark} meta mark set ct mark
        }
      ''
      + lib.optionalString (bypassUids != [ ]) ''

        chain bypass {
          type filter hook output priority mangle;
          meta skuid { ${
            lib.concatMapStringsSep ", " toString bypassUids
          } } meta l4proto { tcp, udp } th dport { 53, 853 } return
          meta skuid { ${lib.concatMapStringsSep ", " toString bypassUids} } meta mark set ${toString mark}
        }
      '';
    };
}
