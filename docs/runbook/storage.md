# Runbook — хранилище

Снимки, внешняя копия, восстановление, откат поколения, scrub, гибернация.
Бюджет ёмкости и порог тревоги — в [`../runbook.md`](../runbook.md) (STO-11).

Владельцы механизмов: `storage/swap` (swap и resume), `storage/maintenance`
(scrub), `storage/backup` (снимки и внешняя копия), `storage/layout` (разметка,
лимит записей загрузчика), `base/nix-settings` (GC).

> Все команды ниже выполняет человек. Разметку (`disko`), `mkfs`, `cryptsetup`
> и удаление поколений ассистент не запускает (ROADMAP W10).

---

## 1. Снимки: что делается само

Таймер `btrbk-system.timer` раз в сутки снимает подтома `rootfs` и `home` в
`/mnt/btrfs-top/snapshots` (`snapshot_create onchange` — без изменений снимок не
создаётся). Хранение: `14d 8w`, минимум `2d`.

Внешнюю цель таймер **не трогает** (`snapshotOnly = true`): носитель подключается
руками.

```sh
systemctl list-timers btrbk-system.timer
systemctl status btrbk-system.service
sudo btrbk -c /etc/btrbk/system.conf list snapshots
```

## 2. Внешняя копия (STO-8, слой «от потери диска»)

Носитель — отдельный **btrfs**-диск, монтируется в `/mnt/backup` (automount или
вручную). Копия считается существующей только после проверки восстановления.

```sh
# 1. Подключить носитель, убедиться, что он смонтирован
findmnt /mnt/backup

# 2. Пробный прогон — ничего не пишет
sudo btrbk -c /etc/btrbk/system.conf --dry-run resume

# 3. Реальная передача (btrfs send | btrfs receive, инкрементально)
sudo btrbk -c /etc/btrbk/system.conf resume

# 4. Что получилось
sudo btrbk -c /etc/btrbk/system.conf list backups
```

Хранение во внешней копии — `30d 12w 12m`, минимум `latest`.

**Ключи (SEC-13).** Источник age-ключа sops — SSH host-ключ, он лежит в
`/etc/ssh` на подтоме `rootfs`, то есть входит в копию вместе с ним. Проверить:

```sh
sudo btrfs subvolume list /mnt/backup | grep rootfs
```

Ключи пользователя (`~/.config/sops/age`) входят вместе с `home`. Отдельная
офлайн-копия ключей хранится **вне диска** (SEC-13) — не в этой процедуре.

**Если носитель не btrfs** — `btrfs send` неприменим, используйте
`rsync -aHAX` по Приложению A ROADMAP либо копирование с шифрованием. Пробное
восстановление обязательно в любом случае.

## 3. Восстановление из снимка (A11)

Снимки btrbk — **только для чтения**. Восстанавливают не «поверх», а копией.

### 3.1 Отдельные файлы (обычный случай)

```sh
sudo btrbk -c /etc/btrbk/system.conf list snapshots        # выбрать метку
ls /mnt/btrfs-top/snapshots/home.<метка>/<пользователь>/
cp -a /mnt/btrfs-top/snapshots/home.<метка>/<пользователь>/<путь> <куда>
```

### 3.2 Подтом целиком

Выполняется **не из работающей сессии** этого пользователя (для `home`) —
с консоли или из установщика.

```sh
# Создать записываемую копию снимка рядом, не удаляя текущий подтом
sudo btrfs subvolume snapshot /mnt/btrfs-top/snapshots/home.<метка> \
                              /mnt/btrfs-top/home.restored

# Переставить местами: старое оставить до проверки
sudo mv /mnt/btrfs-top/home /mnt/btrfs-top/home.broken
sudo mv /mnt/btrfs-top/home.restored /mnt/btrfs-top/home
sudo reboot
```

Старый подтом (`home.broken`) удалять только после проверки, что система и
данные в порядке.

### 3.3 Проверка восстановления (обязательна, STO-8)

Копия без проверки не считается существующей. Периодичность — не реже раза в
квартал, а также после каждой смены носителя.

```sh
# Сравнить содержимое снимка и копии, ничего не меняя
sudo rsync -rcn --delete /mnt/btrfs-top/snapshots/home.<метка>/ \
                          /mnt/backup/<хост>/home.<метка>/ | head
```

Плюс пробное восстановление **образца**: взять один файл по 3.1 из внешней
копии и сверить с оригиналом. Результат и дату записать здесь:

| Дата | Что проверено | Носитель | Результат |
|---|---|---|---|
| — | — | — | *первая проверка — при приёмке R5.2* |

## 4. Откат поколения (OPS-5, A11)

Самый быстрый путь, когда новая система сломана.

```sh
# Из меню systemd-boot: выбрать предыдущее поколение (в меню их до 10 —
# boot.loader.systemd-boot.configurationLimit в storage/layout)

# Из работающей системы — посмотреть список и откатиться загрузкой
nixos-rebuild list-generations
sudo nixos-rebuild boot --rollback && sudo reboot
```

Поколения **до PNR-3 не удаляются** (W5): `nix.gc` запущен без
`--delete-older-than` именно поэтому. Если место кончается — см. порог тревоги
в `runbook.md`, а не удаление поколений.

## 5. Scrub (STO-9)

Раз в месяц, автоматически (`storage/maintenance`). Покрывает всю файловую
систему разом — scrub работает на уровне ФС, а не подтома.

```sh
systemctl list-timers 'btrfs-scrub-*'
sudo btrfs scrub status /
```

Ошибки в выводе scrub — признак проблем с накопителем: снять свежую внешнюю
копию (раздел 2) **до** любых дальнейших действий, затем смотреть SMART.

## 6. Гибернация (STO-5, R5.1)

Смещение swap-файла нужно пересчитывать **при каждом пересоздании файла**
(смена размера, переразметка).

```sh
# 1. Посчитать смещение по уже созданному файлу
just hibernate-offset

# 2. Вписать в modules/hosts/<хост>.nix: my.host.resume.offset = <значение>;
# 3. Применить по OPS-3
just build <хост> && nvd diff /run/current-system result
just test <хост> && just boot <хост>
```

Пока `resume.offset = null`, гибернация недоступна осознанно: политика крышки
остаётся обычным `suspend`, а критический заряд — `PowerOff`
(`flake.lib.host.hibernationReady`, L-12).

**Откат:** вернуть `resume.offset = null` и пересобрать — пункт Hibernate
исчезнет, swap продолжит работать как обычный swap. Либо загрузиться прежним
поколением (раздел 4).
