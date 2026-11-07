# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Политика Nix для DeepSeek Harness (`dsh`) одним патчем (`cordis.patch.yml`
# формата `--patch`, AI-ROLE-5, R9.18). Лаунчер передаёт файл флагом
# `--patch <путь-в-хранилище>` на каждый запуск — в профили в `$DSH_HOME` он
# ничего не пишет: каталог моделей и файл сохранения интерфейса принадлежат
# самому `dsh` (D18). Подключение к шлюзу — переменными окружения
# (`DEEPSEEK_BASE_URL`, `DEEPSEEK_API_KEY`), модель — собственная модель
# провайдера, которую выбирает интерфейс; в патче их нет.
#
# Что и почему выключено (ПРОВЕРЕНО `dsh --dump-config` и README плагинов 0.2.1-rc.3;
# id, которого нет в профиле, `dsh` лишь пропускает с предупреждением):
#   - `web-search-deepseek`, `web-deepseek-api` — резолвят `DEEPSEEK_API_KEY` (у нас
#     там ключ доступа к шлюзу) и шлют его вместе с запросом на `api.deepseek.com`
#     мимо шлюза (R9.14). Анонимная загрузка страниц (`web-fetch-http`) ключа не
#     использует и остаётся; `tool-web.search: false` — поиск в headless и в
#     пресетах не предлагается моделью.
#   - `session-telemetry-otel` → `DISABLED` («транспорт не создаётся»): в режиме по
#     умолчанию `FEEDBACK_ONLY` после отзыва уходит весь журнал сессии на
#     `dsh-otel-collector.deepseeksvc.com`. `product-analytics` и
#     `desktop-product-telemetry` включены только в профиле `desktop` (его лаунчер
#     не запускает).
#   - `session-log-deepseek`, `plugin-package-inventory-deepseek` — расширения
#     запроса: с КАЖДЫМ запросом к API уходят полями `dsh_session_log` (журнал сессии
#     с каталогом запуска и событиями; ПРОВЕРЕНО перехватом запроса заглушкой) и
#     `dsh_plugin_packages` (перечень пакетов). Это загрузка данных провайдеру
#     поверх самого запроса. Патч из `--patch` приоритетнее переключателя в
#     настройках: интерфейс включить его обратно не может.
#   - `plugin-manager`, `tool-plugin-manager`, `ui-plugin-manager` — ставят пакеты из
#     npm в профиль и переписывают его `cordis.patch.yml`: цепочка поставок вне Nix
#     (ARCH-5, AI-GW-13), а у профиля одно место правды — это репозиторий.
#     `entry-customization` — пункты меню «Plugins» — выключается вместе с ними: ему
#     нужна служба `pluginNavigation` от `ui-plugin-manager`, без неё веб-интерфейс
#     падает с «Failed to load plugins … pending (waiting for service: pluginNavigation)»
#     (ПРОВЕРЕНО на машине 2026-11-07; проверка одним HTTP-ответом это не ловит —
#     клиентские записи грузит браузер).
#   Плагина «памяти» в бандлах 0.2.1-rc.3 нет — выключать нечего (ПРОВЕРЕНО по списку
#   записей профилей `web` и `headless`); при обновлении версии перепроверить.
#   Расширения протокола, которые нужны (режим рассуждения `thinking`, `output_config`,
#   `tools`), НЕ трогаем: их должен пропустить шлюз (AI-A17).
{ pkgs }:
pkgs.writeText "dsh-policy.cordis.patch.yml" ''
  # Политика agent-launcher (R9.18) — файл из хранилища, правки только в Nix.
  - id: web-search-deepseek
    disabled: true
  - id: web-deepseek-api
    disabled: true
  - id: tool-web
    config:
      search: false
  - id: session-telemetry-otel
    config:
      mode: DISABLED
  - id: session-log-deepseek
    config:
      enabled: false
  - id: plugin-package-inventory-deepseek
    config:
      enabled: false
  - id: plugin-manager
    disabled: true
  - id: tool-plugin-manager
    disabled: true
  - id: ui-plugin-manager
    disabled: true
  - id: entry-customization
    disabled: true
''
