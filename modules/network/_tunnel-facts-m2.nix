# Приватная часть владельца: tunnel-facts · Домен: network
# Контракт: VPN_SUBSYSTEM §2.3 (реестр my.tunnel.*). Объявления опций режима M2 —
# kill switch, обход и класс маршрутизации `scoped` (STR-6): tunnel-facts.nix
# растёт за счёт них, поэтому они здесь, а не в самом владельце.
# Значения публичны (класс C), секретов нет (SEC-2).
# Импортируется и упоминается только в tunnel-facts.nix (C8).
# Зависимости: —
{ lib }:
{
  # Опции режима M2; вставляются в options.my.tunnel владельцем.
  m2Options = {
    killswitch = {
      allowedInterfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Интерфейсы, исключённые из kill switch, например корпоративный VPN (VPN-KS-2).";
      };

      # VPN-KS-2 разрешает опознавать трафик клиента «по cgroup,
      # пользователю или метке». Выбрана метка: юнит tunnel-xray идёт с
      # DynamicUser (uid нестабилен, CLI-5/M2-6), а путь cgroup nftables
      # разрешает в id при ЗАГРУЗКЕ правил — таблица грузится до сети
      # (VPN-KS-1), когда юнита ещё нет, и загрузка упала бы, отрезав сеть
      # (нарушение VPN-KS-9). Метка от этого свободна.
      mark = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 255;
        description = "SO_MARK сокетов клиента туннеля; по ней kill switch их пропускает (VPN-KS-2).";
      };
    };

    bypass.units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Юниты или слайсы в обход туннеля, например торрент-клиент (MAY, 4.9).";
    };

    # Опция-интерфейс dns-resolver (ADR-34): владелец механизма — он, а
    # вкладывают сюда владельцы линков. Значения — публичные данные
    # политики класса C (VPN-RTE-1), поэтому живут в git, а не читаются из
    # PUSH_REPLY в рантайме.
    dns.scopedZones = lib.mkOption {
      default = [ ];
      description = ''
        Класс маршрутизации `scoped` (VPN-DNS-1): зона → сервер + линк.
        Корпоративный split-horizon: внутренние имена идут в корпоративный
        резолвер через его линк, а не к публичному.
      '';
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            zones = lib.mkOption {
              type = lib.types.nonEmptyListOf lib.types.str;
              description = "DNS-зоны, уходящие на этот сервер (без ведущей точки).";
            };
            server = lib.mkOption {
              type = lib.types.str;
              description = "Адрес резолвера зоны (публичные данные, не секрет — SEC-2 класс C).";
            };
            # Без default: по VPN-DNS-1 опущенный линк — отказ, а не запрос
            # «куда получится». Отсутствие значения ломает сборку намеренно.
            link = lib.mkOption {
              type = lib.types.str;
              description = "Интерфейс, через который доступен сервер. Обязателен (VPN-DNS-1).";
            };
          };
        }
      );
    };
  };
}
