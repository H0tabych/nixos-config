# Фича: code-context · Слот: — · Домен: ai · Классы: H · Для: пользователей с ml
# Контракт: AI_SUBSYSTEM.md §3.5 (AI-CTX-1…6). Уровни: L2 — символьный MCP-сервер
# поверх LSP, L3 — структурный поиск; L0/L1 принадлежат `dev` и проектному окружению.
# Serena (P.1) в nixpkgs нет ни в 26.05, ни в unstable (ПРОВЕРЕНО `nix eval`), а
# сама она при первом запуске качает языковые серверы (AI-CTX-5, R-10). Вместо неё
# mcp-language-server: бинарник без загрузок, LSP-команду получает аргументом.
# AI-CTX-3: Nix даёт только пакеты; список серверов и форматы агентов — в
# dotfiles/ai/. Поэтому в dotfiles лежит имя `code-context-lsp <язык>`, а пути
# store и рабочий каталог подставляет обёртка отсюда (AI-A10).
# AI-CTX-1: LSP ищется в PATH — внутри песочницы это окружение проекта
# (direnv exec, AI-SBX-4), запасной вариант — lsp-global (pyright, clangd).
# rust-analyzer в lsp-global нет (DEV-4): только из проектного окружения.
# AI-CTX-4: stdio, запускается агентом внутри песочницы.
# ПРОВЕРЕНО (R8.7, headless): references на python/cpp/rust совпадают с rg за
# вычетом комментариев. Нюанс clangd: индекс строится после открытия первого
# файла — до этого поиск по имени пуст; агенту сначала hover/definition по файлу.
# Зависимости: нет импорта фич (ARCH-3).
_: {
  flake.modules.homeManager.code-context =
    { pkgs, ... }:
    let
      lspServer = pkgs.writeShellApplication {
        name = "code-context-lsp";
        runtimeInputs = [ pkgs.mcp-language-server ];
        text = ''
          usage() {
            echo "usage: code-context-lsp <python|cpp|rust>" >&2
            exit 1
          }
          [ "$#" -eq 1 ] || usage
          # Клиент dsh запускает сервер со stderr терминала: журналы mcp-language-server и LSP
          # заглушают вывод лаунчера (ссылку веб-интерфейса). Адаптер dsh задаёт файл журнала;
          # у Claude переменной нет — его stderr собирает сам Claude и показывает в /mcp.
          [ -z "''${CODE_CONTEXT_LSP_LOG:-}" ] || exec 2>> "$CODE_CONTEXT_LSP_LOG"

          case "$1" in
            python) lsp=(pyright-langserver --stdio) ;;
            cpp)
              lsp=(clangd)
              # AI-CTX-2: без базы команд компиляции ссылки и вызовы недостоверны.
              if [ ! -e compile_commands.json ] && [ ! -e build/compile_commands.json ]; then
                echo "code-context-lsp: нет compile_commands.json — ссылки C/C++ недостоверны (AI-CTX-2)" >&2
              fi
              ;;
            rust) lsp=(rust-analyzer) ;;
            *) usage ;;
          esac

          # Явная ошибка вместо немого сбоя MCP-клиента (LSP берётся из PATH).
          if ! command -v "''${lsp[0]}" >/dev/null; then
            echo "code-context-lsp: ''${lsp[0]} не найден в PATH (окружение проекта, AI-CTX-1)" >&2
            exit 1
          fi

          exec mcp-language-server --workspace "$PWD" --lsp "''${lsp[0]}" -- "''${lsp[@]:1}"
        '';
      };

      # Браузер для агентов (AI-CTX-4/5): stdio в песочнице, браузеры в пакете, без загрузок.
      # Обёртка с тем же именем `playwright-mcp` (список в dotfiles ссылается на имя из PATH,
      # DOT-1) чинит три причины, по которым браузер не стартовал в песочнице (R9.28):
      #  1. `LD_LIBRARY_PATH` — обёртка claude-code кладёт в него alsa-lib из unstable (glibc 2.43),
      #     chromium собран под glibc 2.42 и падает с `GLIBC_2.43 not found`; дочерним процессам
      #     эта переменная ни к чему;
      #  2. профиль по умолчанию лежит в `PLAYWRIGHT_BROWSERS_PATH` (хранилище, только чтение) —
      #     задаём постоянный профиль в каталоге состояния агента: входы на сайты сохраняются, а
      #     `.playwright-mcp/` не мусорит в проекте (снимки и скриншоты — в каталог состояния);
      #  3. окно открывается на Wayland-сессии пользователя (AI-SBX-15: сокет даёт опция
      #     `--wayland` песочницы); сокета нет (тесты, ВМ, сеанс без Wayland) — без окна.
      playwrightMcp = pkgs.writeShellApplication {
        name = "playwright-mcp";
        text = ''
          unset LD_LIBRARY_PATH
          state="''${XDG_STATE_HOME:-$HOME/.local/state}/playwright-mcp"
          mkdir -p "$state/profile" "$state/output"
          args=(--user-data-dir "$state/profile" --output-dir "$state/output")
          sock="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/''${WAYLAND_DISPLAY:-wayland-1}"
          [ -S "$sock" ] || args+=(--headless)
          exec ${pkgs.playwright-mcp}/bin/playwright-mcp "''${args[@]}" "$@"
        '';
      };
    in
    {
      home.packages = [
        lspServer
        pkgs.ast-grep # L3
        playwrightMcp
      ];
    };
}
