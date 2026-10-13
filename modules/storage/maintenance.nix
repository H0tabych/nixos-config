# Фича: maintenance · Слот: — · Домен: storage · Классы: N · Для: всех хостов с btrfs
# Контракт: STO-9, первая половина («проверки целостности ФС по расписанию»).
# Владеет расписанием scrub. Вторая половина STO-9 — GC и лимит поколений — уже
# поделена между base/nix-settings (nix.gc) и storage/layout
# (boot.loader.systemd-boot.configurationLimit); здесь они не дублируются.
#
# fileSystems задан явно списком из одного пути. По умолчанию опция берёт все
# точки монтирования btrfs, а в нашей разметке (storage/layout) это семь
# подтомов ОДНОЙ файловой системы — scrub прогнал бы одни и те же данные
# семь раз. Это ровно тот случай, о котором предупреждает описание опции:
# scrub работает на уровне файловой системы, а не подтома, поэтому "/"
# покрывает и @home, и @nix, и остальные.
#
# Проверка здоровья накопителя (SMART) — не про целостность ФС и в STO-9 не
# входит; отдельной фичей, если понадобится.
# Зависимости: layout (btrfs на "/") — только чтение точки монтирования (ARCH-3).
_: {
  flake.modules.nixos.maintenance =
    { config, ... }:
    {
      assertions = [
        {
          assertion = config.fileSystems ? "/" && config.fileSystems."/".fsType == "btrfs";
          message = "фича maintenance требует btrfs на / (фича layout) — scrub применим только к btrfs";
        }
      ];

      services.btrfs.autoScrub = {
        enable = true;
        fileSystems = [ "/" ];
        # Рекомендация btrfs-scrub(8) — раз в месяц; на NVMe прогон укладывается
        # в единицы минут, чаще смысла нет.
        interval = "monthly";
      };

      # Привязку к питанию (ConditionACPower) не добавляем: имя юнита autoScrub
      # собирает сама как btrfs-scrub-<escapeSystemdPath путь> — это её
      # внутренняя деталь, и завязываться на неё значило бы ломаться при её
      # смене. Suspend scrub не блокирует: сгенерированный юнит объявлен
      # conflicts с sleep.target, а Persistent = true наверстает пропуск.
    };
}
