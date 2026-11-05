# Runbook — ML и агенты

Восстановление, смена ключей, очистка журналов, перегрузка моделей, измеренные
характеристики и журнал приёмки подсистемы (AI-OPS-5, AI-RES-10, S7).

Владельцы механизмов: `ai/inference-service-ollama` (инференс, `inference-release`,
гибернация), `ai/llm-gateway` (шлюз, секреты пользователя), `ai/agents-tools`
(лаунчер и песочница), `ai/code-context` (MCP и структурный поиск).

> Команды с `sudo`, `just test`/`just boot` и удаление данных выполняет человек
> (ROADMAP W10). Значения ключей здесь не приводятся и в чат не передаются.

---

## 1. Восстановление

### Инференс

```sh
systemctl status ollama.service
curl -s http://127.0.0.1:11434/api/version
curl -s http://127.0.0.1:11434/api/ps       # загруженные модели; size_vram = size → на GPU
```

Инференс ушёл на CPU или не видит GPU после resume (AI-INF-6): штатно это чинит
`inference-post-resume`. Запустить его вручную:

```sh
sudo systemctl start inference-post-resume.service
```

Он останавливает сервис и перезагружает модуль `nvidia_uvm`. Откат не нужен: сервис
поднимается заново, модель загружается по требованию.

### Шлюз

```sh
systemctl --user status llm-gateway
journalctl --user -u llm-gateway -n 50
```

Юнит не должен быть `failed` и без облачных ключей (AI-A14). Единственный источник
настроек — `config.json` от Nix и sops (`source_of_truth`), поэтому `config.db` должна
собираться заново при старте (ПРОВЕРИТЬ: на живой машине не выполнялось). Если база
повреждена, отложите её, а не удаляйте:

```sh
systemctl --user stop llm-gateway
mv ~/.local/state/llm-gateway/config.db ~/.local/state/llm-gateway/config.db.bak
systemctl --user start llm-gateway
```

Откат: остановить юнит и вернуть файл на место.

**Проверка живым запросом** (роль через шлюз; ключ не печатается):

```sh
. ~/.config/machine.d/ai-gateway-env
curl -s "$AI_GATEWAY_URL/v1/chat/completions" \
  -H "Authorization: Bearer $(cat "$AI_GATEWAY_ACCESS_KEY_FILE")" \
  -H 'Content-Type: application/json' \
  -d '{"model":"local-fast","messages":[{"role":"user","content":"Say ok"}],"max_tokens":8}'
```

Ожидается ответ модели, а `/api/ps` показывает загруженную модель. При отказе
смотрите журнал шлюза.

### Песочница агентов

Агент запускается только через `agent-launcher`. Если песочница сломана, он не
стартует (fail-closed, AI-A7), и обходить это нельзя. Поведение проверяет
`tests/agent-sandbox.nix` (`nix flake check`).

Работа агента лежит в отдельном клоне на отдельной ветке (AI-SBX-7):
`~/.local/state/agents/<роль>/`. Push заблокирован, слияние — вручную.

---

## 2. Смена ключей

Секреты пользователя — `secrets/users/<имя>.yaml`. Имена ключей:

| Ключ | Назначение |
|---|---|
| `ai.gateway.accessKey` | Ключ доступа к шлюзу (AI-GW-3/4); префикс шлюза добавляет Nix, в sops он не пишется |
| `ai.gateway.providerKey.<роль>` | Ключ провайдера для облачной роли |
| `ai.gateway.admin.user`, `ai.gateway.admin.pass` | Вход в управляющий API шлюза |

```sh
just sops-edit secrets/users/<имя>.yaml
just build <host> && nvd diff /run/current-system result
just test <host>
systemctl --user restart llm-gateway   # сам юнит при смене секрета не перезапускается
just boot <host>
```

Откат: вернуть файл секретов из git (`git revert`), снова `just test` и перезапуск юнита.
У провайдера старый ключ отзывается после проверки живым запросом (раздел 1).

---

## 3. Очистка журналов и состояния

Журналы локальные, содержимое запросов по умолчанию не пишется (AI-GW-7, AI-SEC-7).

| Что | Где | Перед очисткой |
|---|---|---|
| Журнал запросов шлюза | `~/.local/state/llm-gateway/logs.db*` | Остановить юнит; пересоздание базы при старте — ПРОВЕРИТЬ |
| Журнал юнита | `journalctl --user -u llm-gateway` | Общие лимиты journald |
| Сессии и клоны агентов | `~/.local/state/agents/<роль>/` | **Проверить несмерженные ветки**: здесь лежит работа агента |

```sh
systemctl --user stop llm-gateway
rm ~/.local/state/llm-gateway/logs.db*
systemctl --user start llm-gateway
```

Отката у удаления нет. Если журнал ещё может понадобиться, перенесите его, а не удаляйте.

---

## 4. Модели

```sh
inference-release                                   # выгрузить всё из VRAM; без прав администратора
curl -s http://127.0.0.1:11434/api/tags             # что скачано
curl -s http://127.0.0.1:11434/api/pull -d '{"model":"<тег>"}'     # скачать заново
```

Роли и теги задаёт фича инференса по классу VRAM (AI_SUBSYSTEM P.2), а не dotfiles.
Они попадают в `my.ai.local` и `~/.config/machine.d/ai-env`. Смена тега проходит через
OPS-3; при старте сервис догружает модели сам.

Время жизни в простое — `my.ai.inference.keepAlive` (сейчас `5m`). Одновременно в VRAM
не больше одной модели (AI-RES-1).

---

## 5. Измеренные характеристики

`sgms-laptop`, GTX 1650 (4 ГиБ VRAM), сеть не участвует. Замер 2026-11-05: Ollama 0.32.3,
`qwen2.5-coder:1.5b-base`, FIM-запрос к инференсу напрямую, 32 токена, разные префиксы.

| Показатель | Значение |
|---|---|
| Первый токен, холодный старт (загрузка модели) | 3621 мс |
| Первый токен, медиана / p95 / макс (20 запросов) | 278 / 286 / 290 мс |
| Весь ответ, медиана / p95 | 328 / 357 мс |
| Скорость генерации, медиана | 107 ток/с |
| Занято VRAM моделью | 1,09 ГиБ, модель целиком на GPU (`size_vram = size`) |

В коммите R8.2 (2026-10) записано «~16–23 мс до первого токена». Методика того замера
не сохранилась, и этой серией значение не воспроизведено. Опорным считать таблицу выше.

`local-chat` на классе 3–5 ГБ не объявлен, поэтому его скорость не измерялась (AI_SUBSYSTEM
5.1): чат идёт в облачную роль.

Повторить замер (время до первых байт потокового ответа):

```sh
for i in $(seq 20); do
  curl -s -o /dev/null -w '%{time_starttransfer}\n' http://127.0.0.1:11434/api/generate \
    -d "{\"model\":\"<тег>\",\"prompt\":\"def add_$i(a, b):\",\"suffix\":\"\\n\",\"options\":{\"num_predict\":32}}"
done | sort -n
```

### Бюджет RAM и диска (AI-RES-10)

| Потребитель | Значение | Где |
|---|---|---|
| Модель `local-fast` | 0,92 ГиБ на диске | См. отступление AI-INF-8: сейчас `@rootfs`, по бюджету `@data` |
| Замыкание пакета инференса (CUDA) | 2,1 ГиБ | `@nix` |
| VRAM во время работы модели | 1,09 из 4 ГиБ | Освобождается `keepAlive` или `inference-release` |
| RAM демона и шлюза | Не измерено | Снять вручную: `systemctl status ollama.service`, `systemctl --user status llm-gateway` (строка `Memory`) |

---

## 6. Журнал приёмки AI-A1…A14

Сводка на 2026-11-05. Итоговую приёмку выполняет Gate G8. «Отметка» значит, что шаг
закрыт владельцем в ROADMAP, а заново здесь критерий не проверялся.

| № | Состояние | Основание |
|---|---|---|
| AI-A1 | Да | R8.8, раздел 7 |
| AI-A2 | Да, кроме `local-chat` | Раздел 5; роль на этом классе не объявлена |
| AI-A3 | **Открыт частично** | Модели выгружаются (`/api/ps` пуст); GPU не засыпает, см. раздел 8 |
| AI-A4 | Отметка R8.3 | Хук `game-optimizer` вызывает `inference-release` |
| AI-A5 | **Открыт частично** | Три цикла на GPU (коммит R8.2); пункт про kill switch требует M2 |
| AI-A6 | Отметка R8.5 | |
| AI-A7, AI-A8 | Отметка R8.6 | `tests/agent-sandbox.nix`; для роли AI-SBX-12 набор урезан решением владельца |
| AI-A9 | **Открыт частично** | Облачная роль проверена в M1; проверка в M2 ждёт гейт 7.3 (ADR-35) |
| AI-A10 | Отметка R8.6 | |
| AI-A11 | Отметка R8.7 | Headless-прогон на Python, C/C++, Rust (`ai/code-context`) |
| AI-A12 | Отметка R8.6 | |
| AI-A13 | Да | Раздел 7: проба заменой реализации и живой запрос роли через шлюз |
| AI-A14 | Отметка R8.5 | |

S8 (R8.9): гейт на собственный индекс не пройден, L5 не делаем. Решение и условие
пересмотра — в `docs/adr/ADR-023-code-context-ready-first.md`.

---

## 7. Как проверены AI-A1 и AI-A13 (R8.8, 2026-11-05)

**AI-A1.** `just check` и вычисление обоих хостов:

```sh
nix eval --raw .#nixosConfigurations.sgms-laptop.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.ci-vm.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.ci-vm.config.services.ollama.enable     # false
nix eval --json .#nixosConfigurations.ci-vm.options.my --apply builtins.attrNames   # ["host"]: my.ai нет
```

**AI-A13.** Слот подсистемы один — `inference-service`. Проба на копии дерева вне
репозитория: новая фича-заглушка с тем же контрактом (`my.ai.local`, `inference-release`,
`ai-env`) и одна изменённая строка в `presets/ml.nix`.

- `sgms-laptop` вычисляется, `services.ollama.enable = false`.
- `diff -r` показывает только эти два файла.

Для этого шлюз переведён с провайдера конкретной реализации на OpenAI-совместимый API
(AI-INF-2, ADR-21).

Новый провайдер подтверждён на машине 2026-11-05: владелец применил поколение (`just test`),
запрос роли `local-fast` из раздела 1 прошёл успешно.

Оговорка: в `ai-facts` остаётся дефолт `modelsDir` с именем реализации. На работу заглушки
он не влияет и уйдёт вместе с исправлением AI-INF-8.

---

## 8. Открытые отступления

| Правило | Что не выполняется | Что сделать |
|---|---|---|
| AI-A3, AI-RES-3 | dGPU не уходил в suspended после выгрузки: при `finegrained = false` на устройстве `power/control = on`, `runtime_status = active`, `Runtime D3 status: Disabled by default` (проверено 2026-11-05) | Тест ниже. Блокирует AI-A3 в G8 |
| AI-A5, AI-A9 | Части, зависящие от M2 | Гейт 7.3 (ADR-35) |
| AI-INF-8, STO-1, STO-8 | Модели лежат в `/var/lib/ollama/models`, то есть на `@rootfs`: попадают в снимки корня с бюджетом 10 ГиБ. `backup` не читает `modelsDir` | Отдельный `fix:`, см. ниже |

Предлагаемое исправление AI-INF-8:

1. Дефолт `my.ai.inference.modelsDir` — каталог на томе `/var/lib/nosnapshot` без имени реализации.
2. Права сервиса на этот каталог. У сервиса `DynamicUser`, поэтому механизм проверить сборкой.
3. `backup` читает опцию для исключения (STO-8).
4. Владелец применяет (OPS-3) и скачивает модель заново (раздел 4).

Откат: вернуть дефолт и снова `just test`; модель останется на старом месте, пока
не удалена вручную.

### Тест `finegrained` (AI-A3)

NVIDIA заявляет RTD3 в открытых модулях только с Ampere ([README 595](https://download.nvidia.com/XFree86/Linux-x86_64/595.58.03/README/kernel_open.html)),
а у `sgms-laptop` Turing. Поэтому тест в два этапа. Этап А на открытых модулях (2026-11-05,
драйвер 595.71.05) дал `Runtime D3 status: Not supported`, `runtime_status = active`. Проприетарные модули
Turing поддерживают.

Условия замера: батарея, внешний монитор отключён (hosts/sgms-laptop.md), 10 минут простоя.
`nvidia-smi` не запускать: он будит GPU.

```sh
P=/sys/bus/pci/devices/0000:01:00.0/power
cat $P/control $P/runtime_status $P/runtime_suspended_time
cat /proc/driver/nvidia/gpus/0000:01:00.0/power
upower -i "$(upower -e | grep BAT)" | grep energy-rate
```

| Этап | Что меняется | `runtime_status` | `Runtime D3 status` | Мощность простоя |
|---|---|---|---|---|
| База | `finegrained = false` | active | Disabled by default | Снять |
| А | `finegrained = true` | Снять | Снять | Снять |
| А (2026-11-05) | `open = true`, `finegrained = true` | active, `control = auto` | **Not supported** | Не снимали |
| Б (2026-11-05) | `open = false`, `finegrained = true`; `license: NVIDIA`, `DynamicPowerManagement: 2` | active, `control = auto` | **Not supported** | 18,0 Вт |
| Б2 | то же и `gsp.enable = false` (`NVreg_EnableGpuFirmware=0`) | Снять | Снять | Снять |

Перед Б2 проверено (read-only): chassis_type 10, у корневого порта `PEG0` есть `power_resources_D0` и `power_resources_D3hot` (`_PR0/_PR3`), чипсет HM470, Turing, ядро 6.18.60, CONFIG_PM, persistenced выключен. Условия README 595 выполнены, а драйвер всё равно пишет `Not supported`.

Этап А и Б применяются через `just boot` и перезагрузку: параметры модуля читаются при его
загрузке. Этап Б меняет запись в A.6 Архитектуры и требует заново проверить A7 (CUDA).

Критерий приёмки варианта:

1. После `inference-release` статус `suspended`, мощность простоя ниже базы (AI-A3).
2. Три цикла hibernate подряд, инференс на GPU после каждого (AI-A5).
3. Игра идёт на dGPU, FIM после неё загружается по требованию (AI-A4).

Если устройство всё равно держит процесс, посмотреть `sudo lsof /dev/nvidia*`. Если это демон
инференса, это отдельная находка для фичи инференса.

Откат на любом этапе — предыдущее поколение. Если ни один вариант не прошёл, вернуть
`finegrained = false` и записать исключение AI-A3/A5 здесь; решение по G8 принимает владелец.
