# Фича: agents-tools · Слот: — · Домен: ai · Классы: H · Для: пользователей с ml
# Контракт: AI_SUBSYSTEM.md §3.4 (AI-AGT-1…9, «Лаунчер-песочница» AI-SBX-1…13).
# Агентов три (AI-AGT-1, ADR-47, ADR-52): claude-code (тяжёлый, по подписке), OpenAI Codex CLI
# (по подписке, второй вендор) и DeepSeek Harness `dsh` (альтернативный — другое семейство
# моделей); «контролируемый» — режим `--controlled` того же агента, а не отдельный продукт
# (`aider` удалён, R9.21). Всё знание о конкретном агенте — в адаптере (AI-AGT-9):
# `_agents-tools-claude.nix`, `_agents-tools-codex.nix`, `_agents-tools-dsh.nix`; лаунчер
# (`_agents-tools-launcher.nix`) общий. claude-code в nixpkgs-26.05 отстаёт —
# точечно из pkgs.unstable (ARCH-14, прецедент nix-settings.nix). DeepSeek Harness в 26.05
# нет, в unstable есть (0.2.1-rc.3, с обходом аддона `node-addon-require-builtin`) — берём
# оттуда; собственной деривации нет (R9.18).
# R9.18, ADR-051: `dsh` ходит к DeepSeek напрямую, в родном протоколе (Anthropic Messages на
# `api.deepseek.com/anthropic`), ключ провайдера — `DEEPSEEK_API_KEY` значением из файла фичи
# agents-keys; модель и усилие рассуждения выбирает владелец в интерфейсе. Профили в `$DSH_HOME`
# лаунчер не пишет; политика Nix — патч из хранилища флагом `--patch` (_agents-tools-dsh-policy.nix).
# AI-AGT-4: единственный способ запуска агентов — agent-launcher; необёрнутые бинарники
# агентов в home.packages не попадают. AI-SBX-4: лаунчер активирует проектное окружение
# через уже существующий `direnv` (env-manager-direnv, R6.1) перед запуском.
# AI-SBX-5 (ADR-47, R9.20): песочница — в своём пространстве имён сети и пользователя от
# pasta; соединения идут сокетами хоста (маршруты туннеля и корпоративных VPN, резолвер
# хоста), правила nftables грузит охранник (`agents-net`, `_agents-tools-net.nix`,
# `_agents-tools-nft.nix`). Режим по умолчанию — online; offline — под корнем
# `cloud = "deny"` в `~/.config/ai/roots.toml` или флагом `--offline`. Сети VPN —
# линки `my.tunnel.dns.scopedZones.*.link`; порты служб хоста без аутентификации,
# закрытые агенту, — `my.net.sensitiveLoopbackPorts` (D21). Порт веб-интерфейса dsh — на
# пользователя от `my.ai.gateway.portBase` (+100 + uid − 1000), чтобы не пересекаться со шлюзом.
# AI-SBX-13 (ADR-48): агент, чьи процессы по замыслу разработчиков живут дольше окна
# (claude: супервизор фоновых сессий, `claude agents`), работает в ОДНОЙ долгоживущей
# песочнице на пользователя — транзиентный юнит `agents-<агент>.service`; каждое окно входит
# в неё (`_agents-tools-host.nix`, `agents-host`). Остановить всё: `systemctl --user stop
# agents-claude` (фоновые сессии тоже остановятся).
# Конфиг агента — в dotfiles (AI-AGT-3), под ~/.config/<агент>/. Песочница (AI-SBX-1/2,
# R9.14) собирает корень из разрешённого и возвращает из ~/.config только белый список
# (machine.d, ai, git, direnv) и каталоги агента (`--config`), только чтение; остальной
# ~/.config, в т.ч. ключ расшифровки, не виден.
# AI_SUBSYSTEM.md §2.5: ключ доступа к шлюзу (для инструментов MCP-шлюза) лаунчер кладёт только
# в окружение агента — значение читается из файла `<агент>-<сеть>` в каталоге ключей службы и
# уходит только в переменную окружения процесса агента (`--pass-env`), никогда на диск; при
# отсутствии шлюза (AI-GW-9) агент просто не получает инструментов, а не падает. Ключ провайдера
# (dsh) — файл фичи agents-keys, читается лаунчером так же (ADR-051).
# AI-SBX-7 (ADR-44): работа на месте. Агент работает в текущем дереве проекта
# и коммитит; метаданные git (config, hooks, info, `.envrc`) в песочнице только
# на чтение, общий git-каталог привязан к себе, `.direnv` у роли свой
# (_agents-tools-sandbox.nix). После сессии лаунчер печатает отчёт
# (_agents-tools-git.nix): сдвинутые ссылки, флаги индекса,
# вложенные репозитории, изменённые игнорируемые файлы. Слияние и публикация —
# только человек.
# Зависимости: нет импорта фич (ARCH-3); `direnv` берётся как пакет через
# pkgs.direnv, активация — дело env-manager-direnv на хосте (FEAT-8).
_: {
  flake.modules.homeManager.agents-tools =
    {
      pkgs,
      lib,
      osConfig,
      ...
    }:
    let
      gitTool = pkgs.callPackage ./_agents-tools-git.nix { };
      docsTool = pkgs.callPackage ./_agents-tools-docs.nix { };
      nftTool = pkgs.callPackage ./_agents-tools-nft.nix { };
      # Сети VPN — линки корпоративных зон туннеля; на хосте без туннеля список пуст.
      vpnLinks = map (z: z.link) (lib.attrByPath [ "my" "tunnel" "dns" "scopedZones" ] [ ] osConfig);
      netTool = pkgs.callPackage ./_agents-tools-net.nix {
        inherit nftTool vpnLinks;
        sensitivePorts = osConfig.my.net.sensitiveLoopbackPorts;
      };
      sandboxExec = pkgs.callPackage ./_agents-tools-sandbox.nix {
        inherit gitTool;
        mounts = import ./_agents-tools-sandbox-mounts.nix;
      };
      dshWebPortBase = osConfig.my.ai.gateway.portBase + 100;

      # claude-code из unstable отстаёт от выпуска поставщика (2.1.317 при 2.1.323, ПРОВЕРЕНО
      # 2026-11-13). Пакет берёт версию и сумму бинарника из аргумента `manifest` — подменяем
      # только его (значения — manifest.zst.json выпуска 2.1.323). Закрепление отключается
      # само, когда unstable догонит версию (ARCH-14, AI-AGT-2).
      claudePin = {
        version = "2.1.323";
        platforms.linux-x64 = {
          binary = "claude.zst";
          checksum = "d5f85ac4e9b7ca95e6bbeeeaf05af7c20ff62ddd2a0f49b1f4a0699c30ab0686";
        };
      };
      claudeBase = pkgs.unstable.claude-code;
      claudeCode =
        if
          pkgs.stdenv.hostPlatform.system == "x86_64-linux"
          && lib.versionOlder claudeBase.version claudePin.version
        then
          claudeBase.override { manifest = claudePin; }
        else
          claudeBase;
      # Версия — из закреплённого unstable (ПРОВЕРИТЬ политику при каждом обновлении:
      # `dsh --dump-config`, список записей в _agents-tools-dsh-policy.nix).
      deepseekHarness = pkgs.unstable.deepseek-harness;

      # Codex CLI: в 26.05 версия 0.146.0, в unstable — актуальная; точечно из unstable
      # (ARCH-14, как у claude-code и dsh). Пакет — нативный Rust-бинарник, не npm.
      codexCode = pkgs.unstable.codex;

      # Политика Nix для dsh (поиск, телеметрия, менеджер плагинов) — в хранилище.
      dshPolicy = pkgs.callPackage ./_agents-tools-dsh-policy.nix { };

      # Адаптеры (AI-AGT-9): всё знание о конкретном агенте — в них, лаунчер общий.
      adapters = [
        (pkgs.callPackage ./_agents-tools-claude.nix { inherit claudeCode; })
        (pkgs.callPackage ./_agents-tools-dsh.nix {
          inherit deepseekHarness dshPolicy;
          webPortBase = dshWebPortBase;
        })
        (pkgs.callPackage ./_agents-tools-codex.nix { inherit codexCode; })
      ];

      hostTool = pkgs.callPackage ./_agents-tools-host.nix {
        inherit netTool sandboxExec adapters;
      };

      agentLauncher = pkgs.callPackage ./_agents-tools-launcher.nix {
        inherit
          sandboxExec
          netTool
          gitTool
          docsTool
          hostTool
          adapters
          ;
      };
    in
    {
      # AI-AGT-9: у адаптера с моделью через шлюз должна быть запись в
      # `my.ai.gateway.agents` (иначе нет ключей `<агент>-<сеть>`); на сборке, не в рантайме.
      assertions = map (a: {
        assertion = lib.hasAttr a.name osConfig.my.ai.gateway.agents;
        message =
          "agents-tools: у агента `${a.name}` (адаптер с ключом шлюза) нет записи "
          + "my.ai.gateway.agents.${a.name} (AI-AGT-9). Есть: "
          + lib.concatStringsSep ", " (lib.attrNames osConfig.my.ai.gateway.agents);
      }) (lib.filter (a: a.gatewayKey) adapters);

      home.packages = [ agentLauncher ];
    };
}
