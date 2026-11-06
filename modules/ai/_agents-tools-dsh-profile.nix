# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# Патчи профилей DeepSeek Harness (`cordis.patch.yml`) для agent-launcher.
# Собираются в хранилище, а не печатаются printf'ом в рантайме, чтобы политику
# можно было проверить при сборке (tests/agent-sandbox.nix). Плейсхолдер
# `@GATEWAY_URL@` лаунчер подставляет при запуске (адрес — из машинного слоя).
#
# Встроенный поиск выключен (R9.14, AI-A17): провайдеры `web-search-deepseek`
# и `web-deepseek-api` резолвят DEEPSEEK_API_KEY — а там НАШ ключ доступа к
# шлюзу — и шлют его вместе с запросом на `api.deepseek.com`, мимо шлюза.
# Без провайдера `web_search` возвращает структурную ошибку и никуда не ходит.
# ID проверены по `packages/bundle/base/cordis.patch.yml` версии 0.2.1-rc.3.
# Анонимная загрузка (`web-fetch-http`) ключа не использует — остаётся до R9.18.
# `tool-web` описан только в headless: в `web` строка отключена на хосте, а
# инструменты собирают пресеты — там достаточно отсутствия провайдера.
# `provider: deepseek-official` — внутреннее имя маршрута dsh, не выбор
# провайдера: реальный провайдер за ролью решает шлюз.
{ pkgs, dshRole }:
let
  common = ''
    # Сгенерировано agent-launcher (R8.6, R9.14) — правки будут перезаписаны.
    - id: llm-deepseek
      config:
        baseURL: @GATEWAY_URL@/anthropic
    - id: agent-default-model
      config:
        provider: deepseek-official
        model: ${dshRole}
    - id: web-search-deepseek
      disabled: true
    - id: web-deepseek-api
      disabled: true
  '';
in
{
  web = pkgs.writeText "dsh-web.cordis.patch.yml" common;
  headless = pkgs.writeText "dsh-headless.cordis.patch.yml" (
    common
    + ''
      - id: tool-web
        config:
          search: false
    ''
  );
}
