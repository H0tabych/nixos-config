# Фича: mcp-jira · Слот: — · Домен: ai · Классы: N · Для: хоста с ml
# Контракт: AI-GW-14 (инструменты с секретом запускает шлюз под своей учётной записью; агент
# токена не получает), AI-CTX-5 (загрузки кода из сети во время работы нет), AI_SUBSYSTEM.md §3.
# Сервер трекера задач — `mcp-atlassian`: в nixpkgs его нет ни в 26.05, ни в unstable
# (ПРОВЕРЕНО `nix eval`/`nix search`, 2026-11-14), раньше запускался `uvx mcp-atlassian@latest`
# из сети. Вход шаблонного типа с фиксированной версией (AI-CTX-5): готовые колёса PyPI с
# зафиксированным хэшем, зависимости — из nixpkgs. Версия 0.23.1 (2026-08-19) — последняя,
# чьи требования отличаются от nixpkgs 26.05 лишь минимальными версиями `fastmcp` (3.2.4 против
# 3.2.3), `mcp` (1.27 против 1.26), `fakeredis` (<2.35 против 2.36), поэтому ограничения версий
# сняты (`pythonRelaxDeps`); работоспособность ПРОВЕРЕНА запуском по stdio (initialize,
# tools/list — 63 инструмента) 2026-11-14. Заглушки типов (`types-*`) в рантайме не нужны.
# Серверу нужен адрес (`my.ai.gateway.mcp.jira.env.JIRA_URL` — задаёт хост, это адрес во
# внутренней сети) и личный токен (секрет `ai.gateway.mcpToken.jira`, подставляет обёртка шлюза).
# Состав доступа ключам агентов — хост (`my.ai.gateway.agents.<агент>.mcp`).
# Зависимости: ai-facts (my.ai.gateway.mcp) — схема my.*, состав — пресетом ml (ARCH-3).
_: {
  flake.modules.nixos.mcp-jira =
    { config, pkgs, ... }:
    let
      py = pkgs.python3Packages;
      wheel =
        pname: version: sha256:
        py.fetchPypi {
          inherit pname version sha256;
          format = "wheel";
          dist = "py3";
          python = "py3";
        };

      markdownToConfluence = py.buildPythonPackage {
        pname = "markdown-to-confluence";
        version = "0.6.0";
        format = "wheel";
        src =
          wheel "markdown_to_confluence" "0.6.0"
            "22a4d74345cc42ebe9733b26cc9cf7c43c9413bc613af24733a229756abc390a";
        dependencies = with py; [
          cattrs
          lxml
          markdown
          orjson
          pymdown-extensions
          pyyaml
          requests
          truststore
        ];
        pythonRelaxDeps = true;
        doCheck = false;
      };

      mcpAtlassian = py.buildPythonApplication {
        pname = "mcp-atlassian";
        version = "0.23.1";
        format = "wheel";
        src =
          wheel "mcp_atlassian" "0.23.1"
            "2c00820dabb6d39d9356025a52689cbc411ec4f7d7dd87a64589099084da471a";
        dependencies =
          (with py; [
            anyio
            atlassian-python-api
            beautifulsoup4
            cachetools
            click
            fakeredis
            fastmcp
            httpx
            keyring
            markdown
            markdownify
            mcp
            pydantic
            python-dateutil
            python-dotenv
            requests
            socksio
            starlette
            thefuzz
            trio
            truststore
            unidecode
            urllib3
            uvicorn
          ])
          ++ [ markdownToConfluence ];
        pythonRelaxDeps = true;
        pythonRemoveDeps = [
          "types-cachetools"
          "types-python-dateutil"
        ];
        doCheck = false;
      };
      jira = config.my.ai.gateway.mcp.jira;
    in
    {
      my.ai.gateway.mcp.jira = {
        type = "stdio";
        command = "${mcpAtlassian}/bin/mcp-atlassian";
        secret = true;
        secretEnv = "JIRA_PERSONAL_TOKEN";
        env.FASTMCP_SHOW_SERVER_BANNER = "false";
      };

      assertions = [
        {
          assertion = jira.env ? JIRA_URL;
          message = "my.ai.gateway.mcp.jira.env.JIRA_URL: адрес трекера задаёт хост (mcp-jira).";
        }
      ];
    };
}
