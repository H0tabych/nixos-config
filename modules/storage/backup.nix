# Фича: backup · Слот: — · Домен: storage · Классы: N · Для: хостов с btrfs
# Контракт: STO-8 (локальные снимки + копия на внешний носитель, проверка
# восстановления, ключи в бэкапе — SEC-13; хранилища моделей и кэши исключены).
# Владеет расписанием снимков, политикой хранения и монтированием верхнего
# уровня btrfs, нужного для работы со подтомами (Приложение A ROADMAP).
#
# Два слоя одним конфигом — штатный приём btrbk (snapshotOnly: «useful when you
# want to manually backup to an external drive that might not always be
# connected»): таймер делает ТОЛЬКО снимки и никогда не трогает внешнюю цель,
# а копия снимается вручную, когда носитель подключён:
#   sudo btrbk -c /etc/btrbk/system.conf resume
# Процедура и проверка восстановления — docs/runbook.md (STO-8, A11).
#
# Что входит: подтома rootfs (вместе с /etc/ssh — источник age-ключа sops, SEC-13)
# и home (включая ~/.config/sops/age). Что НЕ входит: подтом data
# (/var/lib/nosnapshot) — модели, игровая библиотека, образы контейнеров: он
# просто не перечислен, поэтому STO-1/STO-8 выполняются составом, а не исключениями.
# ⚠ РАСХОЖДЕНИЕ со STO-8 в части «кэши исключены»: ~/.cache лежит внутри подтома
# home, а btrfs send/receive не умеет исключать подкаталоги. Для локальных снимков
# это почти бесплатно (CoW), но во внешнюю копию кэш уезжает. Снимается только
# выделением ~/.cache в отдельный подтом — это правка layout, то есть разметки
# (PNR-2), поэтому отложено; зафиксировать в реестре отступлений runbook.
# Зависимости: layout (btrfs, подтома rootfs/home/snapshots), host-facts
# (my.host.name) — через config, без импорта фич (ARCH-3).
_: {
  flake.modules.nixos.backup =
    { config, lib, ... }:
    let
      topLevel = "/mnt/btrfs-top";
      # Опции btrfs действуют на всю ФС и задаются единообразно (STO-1), поэтому
      # берутся у уже описанного корня, а не переписываются литералом: иначе при
      # правке layout набор разъехался бы. Снимаются только привязка к конкретному
      # подтому и initrd-флаг — здесь монтируется верхний уровень (subvolid=5).
      topLevelOptions =
        (lib.filter (
          o: !(lib.hasPrefix "subvol=" o || lib.hasPrefix "subvolid=" o || o == "x-initrd.mount")
        ) config.fileSystems."/".options)
        ++ [ "subvolid=5" ];
    in
    {
      assertions = [
        {
          assertion = config.fileSystems ? "/" && config.fileSystems."/".fsType == "btrfs";
          message = "фича backup требует btrfs на / (фича layout): снимки делаются подтомами";
        }
      ];

      # Снимки должны лежать вне смонтированных подтомов, иначе попадают сами в
      # себя (Приложение A ROADMAP). Цель внешней копии (/mnt/backup) не
      # объявляется здесь: носитель подключается руками и монтируется automount.
      fileSystems.${topLevel} = {
        device = config.fileSystems."/".device;
        fsType = "btrfs";
        options = topLevelOptions;
      };

      services.btrbk.instances.system = {
        onCalendar = "daily";
        # Таймер — только снимки; внешняя цель ниже используется ручным `resume`.
        snapshotOnly = true;

        settings = {
          # Несколько снимков в сутки различимы по времени, а не только по дате.
          timestamp_format = "long";

          # Хранение локальных снимков (срок — часть бюджета ёмкости, STO-11).
          snapshot_preserve_min = "2d";
          snapshot_preserve = "14d 8w";

          # Во внешней копии держим дольше: это слой от потери диска.
          target_preserve_min = "latest";
          target_preserve = "30d 12w 12m";

          volume.${topLevel} = {
            # Подтом /snapshots зарезервирован в layout именно под это (STO-9).
            snapshot_dir = "snapshots";
            target = "/mnt/backup/${config.my.host.name}";
            # "onchange" сравнивает generation подтома с ПОСЛЕДНИМ снимком —
            # при первом запуске последнего снимка нет, и btrbk 0.32.7 в этом
            # случае ничего не создаёт (проверено на машине: таймер отработал
            # с exit 0, каталог snapshots остался пустым). "always" гарантирует
            # первый снимок и не плодит проблему дальше — ценой снимка раз в
            # сутки даже без изменений, что для `home`/`rootfs` пренебрежимо.
            snapshot_create = "always";

            subvolume = {
              rootfs = { };
              home = { };
            };
          };
        };
      };
    };
}
