# ADR-52: Codex — подписочный агент второго вендора

- Статус: принято 2026-11-25 (решение владельца); реализация — ROADMAP.md R9.28: адаптер
  `_agents-tools-codex.nix`, `agents-tools.nix`, `hosts/sgms-laptop.nix` (`agents.codex.mcp`),
  `dotfiles/ai` (`generated/codex/`, `.codex/AGENTS.md`). Уточняет ADR-47 (условие пересмотра).
- Контекст: ADR-47 отклонял Codex как *контролируемый* агент (режим автономного, а не третий продукт).
  Здесь он вводится не как режим, а как самостоятельный подписочный агент второго вендора рядом с
  `claude`.
- Решение:
  - Пакет — `pkgs.unstable.codex` (в 26.05 — 0.146.0, в unstable — актуальная; нативный Rust-бинарник),
    ARCH-14. Запуск — только через `agent-launcher codex` (AI-AGT-4).
  - Модель — по подписке ChatGPT, в родном протоколе агента, мимо шлюза (AI-GW-11); в `offline` не
    запускается (`cloudOnly`). Вход — один раз: `agent-launcher codex login --device-auth` (обратный
    вызов на `127.0.0.1:1455` вне песочницы не виден, код вводится в браузере хоста).
  - Домашний каталог — ослабленный режим AI-SBX-12 (`--home-rw`): состояние Codex — `~/.codex`.
    Точечная альтернатива: `--app-path ~/.codex` и `CODEX_HOME`, цена — каталог создать руками до первого
    запуска.
  - Политика уровня 0 — опциями запуска `-c ключ=значение` (DOT-3: `~/.codex/config.toml` ведёт сам Codex):
    `approval_policy="on-request"`; `autonomous` — `sandbox_mode="danger-full-access"` (границу даёт
    песочница лаунчера, AI-SBX-8), `controlled` — `workspace-write` (вложенная песочница Codex внутри
    песочницы лаунчера — ПРОВЕРИТЬ; не заработает — `untrusted` и `read-only`). Телеметрия и проверка
    обновлений выключены ключами `analytics.enabled=false`, `check_for_update_on_startup=false`
    (`DO_NOT_TRACK` Codex не читает — ПРОВЕРЕНО по бинарнику 0.166.0).
  - MCP (AI-CTX-3): локальные серверы общего списка — `ai/generated/codex/local.overrides` (генератор
    `gen.py`), вход MCP-шлюза — `$AI_GATEWAY_URL/mcp` с заголовком `x-bf-vk` из окружения
    (`env_http_headers`); ключ шлюза `codex-online` — только для инструментов.
  - Инструкции: глобальный `AGENTS.md` — ссылка `~/.codex/AGENTS.md` ← `ai/AGENTS.md` (`dotfiles-link`);
    навыки — общий `~/.agents/skills`.
- Условие пересмотра ADR-47 выполнено решением владельца; замер на наборе 8.2 (R9.24) — к проверке.
- Применение: пересборка и вход в подписку — владелец.
