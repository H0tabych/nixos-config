# Документация nixos-config

Оглавление каталога документации (схема — STRUCTURE.md §6).

## Архитектура

Нормативные документы, разделы ищите по ID правила (`grep -n "<ID>" docs/architecture/*.md`):

- [`architecture/ARCHITECTURE.md`](architecture/ARCHITECTURE.md) — нормативная архитектура, критерии приёмки A1–A18
- [`architecture/STRUCTURE.md`](architecture/STRUCTURE.md) — структура репозитория, проверки C1–C13
- [`architecture/VPN_SUBSYSTEM.md`](architecture/VPN_SUBSYSTEM.md) — туннель, DNS, kill switch
- [`architecture/AI_SUBSYSTEM.md`](architecture/AI_SUBSYSTEM.md) — инференс, шлюз, агенты
- [`architecture/DESIGN_SYSTEM.md`](architecture/DESIGN_SYSTEM.md) — дизайн-система рабочего стола: стекло, палитра, токены, профили эффектов
- [`architecture/ROADMAP.md`](architecture/ROADMAP.md) — дорожная карта; шаги `R<этап>.<n>`, Gate'ы `G<n>`

## Хост

- [`hosts/sgms-laptop.md`](hosts/sgms-laptop.md) — аппаратная спецификация ноутбука (laptop_spec)

## Решения (ADR)

[`adr/`](adr/) — файл на каждую запись реестра ADR (ARCHITECTURE.md §21, с дополнениями STRUCTURE.md). Реестр — краткий список решений; поля контекст/решение/причина/затронутые правила — в файле `adr/ADR-<NNN>-<тема>.md`.

Исключение: ADR-20…24 и ADR-25…29 принадлежат подсистемам и записаны в `AI_SUBSYSTEM.md` (раздел 9) и `VPN_SUBSYSTEM.md` (раздел 8); отдельных файлов у ADR-25…29 нет — дублировать их незачем (ARCH-5). Файлы ADR-20…24 в `adr/` есть как краткие записи.

## Эксплуатация

[`runbook.md`](runbook.md) — единственная точка входа (OPS-8); темы — в `runbook/`:

- [`runbook/recovery.md`](runbook/recovery.md) — восстановление: откат, снимки, переустановка с нуля
- [`runbook/keys.md`](runbook/keys.md) — замена и ротация ключей sops
- [`runbook/storage.md`](runbook/storage.md), [`runbook/tunnel.md`](runbook/tunnel.md), [`runbook/ai.md`](runbook/ai.md), [`runbook/design-system.md`](runbook/design-system.md), [`runbook/portability.md`](runbook/portability.md) — по подсистемам

## Установка

Установка на чистую машину — ARCHITECTURE.md §18.9; ручной порядок и ограничения (`just bootstrap` —
заготовка, не реализован) — в [`runbook/recovery.md`](runbook/recovery.md), раздел 2. Применение
изменений на уже установленной системе — OPS-3 (`just build` → `nvd diff` → `just test` → `just boot`).
