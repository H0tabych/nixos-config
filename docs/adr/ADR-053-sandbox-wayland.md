# ADR-53: окно браузера агента — сокет Wayland и GL в песочнице (`--wayland`)

- Статус: принято 2026-11-25 (решение владельца); реализация — `modules/ai/_agents-tools-sandbox.nix`,
  `_agents-tools-sandbox-mounts.nix`, обёртка `playwright-mcp` в `code-context.nix`, адаптеры всех
  трёх агентов, проверка в `tests/agent-sandbox.nix`. Уточняет AI-SBX-1.
- Источник: Playwright (`playwright-mcp`) не запускался ни у одного агента (проверено живьём, 2026-11-25).
  Три независимые причины:
  1. обёртка `claude-code` экспортирует `LD_LIBRARY_PATH` с alsa-lib из unstable (glibc 2.43), а chromium
     из playwright собран под glibc 2.42 — `GLIBC_2.43 not found` (страдает claude и его дочерние процессы);
  2. профиль браузера по умолчанию создаётся в `PLAYWRIGHT_BROWSERS_PATH` (хранилище, только чтение) —
     `ENOENT mkdir` (все три агента);
  3. режим с окном требует сокет Wayland, а `/run/user/<uid>` песочницы пуст (все три агента).
- Решение:
  - Обёртка `playwright-mcp` (то же имя, DOT-1): `unset LD_LIBRARY_PATH`; постоянный профиль и каталог
    вывода в `$XDG_STATE_HOME/playwright-mcp` (входы на сайты сохраняются, проект не мусорится); окно по
    умолчанию, без сокета Wayland — автоматически `--headless`.
  - Опция `agents-sandbox-exec --wayland` (AI-SBX-15): один сокет `$WAYLAND_DISPLAY` (иначе первый
    `wayland-*`) в `/run/user/<uid>`, `WAYLAND_DISPLAY`, `XDG_SESSION_TYPE=wayland`, `/run/opengl-driver`
    (только чтение). Адаптеры `claude`, `dsh`, `codex` включают её вместе с `--device dri` (AI-SBX-14).
    Проверено ВМ-тестом: сокет виден и отвечает изнутри, прочие сокеты `/run/user` скрыты.
- Риск (принят владельцем): клиент Wayland в песочнице видит окна, ввод и буфер обмена сессии в
  пределах протоколов Hyprland. Смягчение — ограниченный сокет через `wp_security_context_v1`
  (Hyprland 0.55 его поддерживает; готового инструмента в nixpkgs нет — отдельный шаг).
- Отклонено: только `--headless` (владелец хочет видеть окно и входить в аккаунты руками); бинд всего
  `/run/user/<uid>` — открыл бы шину сессии, `gpg-agent`, `pipewire`.
- Применение: пересборка и перезапуск долгоживущей песочницы claude (`systemctl --user stop
  agents-claude`) — владелец. Работа GL (иначе — программный рендеринг) и выбор `ozone-platform` —
  ПРОВЕРИТЬ на машине.
