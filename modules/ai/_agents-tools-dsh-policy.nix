# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Политика Nix для DeepSeek Harness (`dsh`) одним патчем (`cordis.patch.yml`
# формата `--patch`, R9.18, ADR-051). Лаунчер передаёт файл флагом
# `--patch <путь-в-хранилище>` на каждый запуск — в профили в `$DSH_HOME` он
# ничего не пишет: каталог моделей и файл сохранения интерфейса принадлежат
# самому `dsh` (D18). Подключение к провайдеру — переменная окружения
# `DEEPSEEK_API_KEY` (ключ провайдера, адрес — умолчание dsh), модель и усилие рассуждения
# выбирает владелец в интерфейсе; в патче их нет.
#
# Родной поиск и загрузка страниц DeepSeek (`web-search-deepseek`, `web-deepseek-api`,
# `tool-web`) РАБОТАЮТ: пока ключом был ключ шлюза, они были отключены (он утёк бы на
# `api.deepseek.com` мимо шлюза), с ADR-051 ключ — провайдера, и запросы идут по назначению.
#
# Что и почему выключено (ПРОВЕРЕНО `dsh --dump-config` и README плагинов 0.2.1-rc.3;
# id, которого нет в профиле, `dsh` лишь пропускает с предупреждением):
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
#   `tools`), НЕ трогаем: они идут провайдеру как есть, без посредника (AI-A17).
{ pkgs }:
pkgs.writeText "dsh-policy.cordis.patch.yml" ''
  # Политика agent-launcher (R9.18) — файл из хранилища, правки только в Nix.
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
