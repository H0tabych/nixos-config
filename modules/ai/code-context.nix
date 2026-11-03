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
    in
    {
      home.packages = [
        lspServer
        pkgs.ast-grep # L3
      ];
    };
}
