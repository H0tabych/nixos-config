# Документация nixos-config

Оглавление каталога документации (схема — STRUCTURE.md §6).

## Архитектура

Нормативные документы, разделы ищите по ID правила (`grep -n "<ID>" docs/architecture/*.md`):

- [`architecture/ARCHITECTURE.md`](architecture/ARCHITECTURE.md) — нормативная архитектура, критерии приёмки A1–A18
- [`architecture/STRUCTURE.md`](architecture/STRUCTURE.md) — структура репозитория, проверки C1–C11
- [`architecture/VPN_SUBSYSTEM.md`](architecture/VPN_SUBSYSTEM.md) — туннель, DNS, kill switch
- [`architecture/AI_SUBSYSTEM.md`](architecture/AI_SUBSYSTEM.md) — инференс, шлюз, агенты
- [`architecture/ROADMAP.md`](architecture/ROADMAP.md) — дорожная карта; шаги `R<этап>.<n>`, Gate'ы `G<n>`

## Хост

- [`hosts/sgms-laptop.md`](hosts/sgms-laptop.md) — аппаратная спецификация ноутбука (laptop_spec)

## Решения (ADR)

[`adr/`](adr/) — файл на каждую запись реестра ADR (ARCHITECTURE.md §21, с дополнениями STRUCTURE.md и VPN_SUBSYSTEM.md). Реестр — краткий список решений; поля контекст/решение/причина/затронутые правила — в файле `adr/ADR-<NNN>-<тема>.md`.

## Что появится позже

- `runbook.md` и `runbook/<тема>.md` — восстановление, откат, замена ключей; создаются на шаге R9.6
