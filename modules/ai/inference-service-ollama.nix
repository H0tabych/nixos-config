# Фича: inference-service-ollama · Слот: inference-service · Домен: ai · Классы: N · Для: хоста с ml
# Контракт: AI-INF-1…12 (AI_SUBSYSTEM.md §3.1), AI-RES-1…3 (§5.1-5.2). Пакет и теги
# моделей — ПРОВЕРИТЬ перед первой сборкой (Приложение P.2/P.3: эскиз помечен
# «синтаксис проверить сборкой»); API inference-release (/api/ps, keep_alive) —
# ПРОВЕРИТЬ живым вызовом (не подтверждается статическим анализом). Pre-sleep/post-resume
# (AI-INF-6) — первый такой паттерн в репозитории; порядок целей — ПРОВЕРИТЬ на хосте.
# R8.4 (AI-CMP-4): адрес инференса и роль→модель пишутся в machine.d/ai-env —
# тот же приём, что zsh-env у shell-zsh.nix (сама фича пишет файл в каталог,
# которым владеет dotfiles-link, DOT-5/§2.4 AI_SUBSYSTEM.md); dotfiles читают
# переменные, именам моделей там взяться нельзя (AI-ROLE-2, DOT-1/DOT-6).
# Зависимости: host-facts (my.host.gpu.*), ai-facts (my.ai.*) — только чтение значений,
# состав — пресетом ml (ARCH-3).
{ lib, ... }:
{
  flake.modules.nixos.inference-service-ollama =
    { config, pkgs, ... }:
    let
      gpu = config.my.host.gpu;
      inference = config.my.ai.inference;

      pkg =
        {
          cuda = pkgs.ollama-cuda;
          vulkan = pkgs.ollama-vulkan;
          none = pkgs.ollama-cpu;
        }
        .${gpu.compute};

      # Теги — ПРОВЕРИТЬ по карточкам моделей (P.2).
      roles =
        if gpu.compute == "none" || gpu.vramGiB == null then
          { }
        else if gpu.vramGiB >= 6 then
          {
            local-fast = "qwen2.5-coder:1.5b-base";
            local-chat = "qwen2.5-coder:7b";
          }
        else if gpu.vramGiB >= 3 then
          { local-fast = "qwen2.5-coder:1.5b-base"; }
        else
          { };

      inferenceRelease = pkgs.writeShellScriptBin "inference-release" ''
        set -euo pipefail
        url="http://${inference.host}:${toString inference.port}"
        # ПРОВЕРИТЬ: путь /api/ps и поле .models[].name — по документации Ollama.
        models=$(${pkgs.curl}/bin/curl -sf "$url/api/ps" | ${pkgs.jq}/bin/jq -r '.models[]?.name')
        for m in $models; do
          ${pkgs.curl}/bin/curl -sf "$url/api/generate" \
            -d "{\"model\":\"$m\",\"keep_alive\":0}" >/dev/null || true
        done
      '';

      # Ollama определяет GPU один раз, при старте. На загрузке он стартует раньше, чем udev
      # поднял модуль NVIDIA и появились устройства (2026-11-06: обнаружение в 13:02:34.9, а
      # nvidia_uvm и nvidia-drm загрузились в 13:02:35), и сервис молча оставался на CPU до
      # первого перезапуска (AI-INF-6, AI-A5: «без ручных действий»). Поэтому перед стартом
      # ждём драйвер с ограничением по времени и подгружаем nvidia_uvm — как post-resume ниже.
      # Нет драйвера за отведённое время — старт не блокируется: сервис работает на CPU, а
      # причина остаётся в журнале.
      gpuReady = pkgs.writeShellScript "inference-gpu-ready" ''
        wait_for() { # условие, секунды
          for _ in $(${pkgs.coreutils}/bin/seq 1 $(( $2 * 10 ))); do
            eval "$1" && return 0
            ${pkgs.coreutils}/bin/sleep 0.1
          done
          return 1
        }
        wait_for '[ "$(${pkgs.coreutils}/bin/cat /sys/module/nvidia/initstate 2>/dev/null)" = live ]' 30 \
          || { echo "inference-gpu-ready: драйвер NVIDIA не поднялся за 30 с, сервис стартует без GPU" >&2; exit 0; }
        ${pkgs.kmod}/bin/modprobe nvidia_uvm || true
        wait_for '[ -e /dev/nvidia-uvm ]' 10 \
          || echo "inference-gpu-ready: /dev/nvidia-uvm не появился за 10 с" >&2
      '';
    in
    {
      my.ai.local = roles;

      services.ollama = {
        enable = true;
        package = pkg;
        inherit (inference) host;
        inherit (inference) port;
        models = inference.modelsDir;
        loadModels = lib.attrValues roles;
        environmentVariables = {
          OLLAMA_KEEP_ALIVE = inference.keepAlive;
          OLLAMA_MAX_LOADED_MODELS = "1"; # AI-RES-1
        };
      };

      environment.systemPackages = [ inferenceRelease ];

      # "+": модуль грузит root, основной процесс остаётся в песочнице сервиса.
      systemd.services.ollama.serviceConfig.ExecStartPre = lib.mkIf (gpu.compute == "cuda") [
        "+${gpuReady}"
      ];

      # AI-INF-8: каталог моделей лежит на томе данных, а не в состоянии сервиса, поэтому его
      # владелец должен быть известен заранее. При DynamicUser UID выбирается при старте, и
      # создать каталог с нужным владельцем нельзя. Поэтому у сервиса статическая учётная
      # запись: systemd при DynamicUser=yes использует уже существующего пользователя с таким
      # именем, а песочница сервиса (ProtectSystem=strict, ReadWritePaths на models) остаётся.
      # Имя — сервисная учётная запись, не пользователь системы (ARCH-17).
      services.ollama = {
        user = "ollama";
        group = "ollama";
      };

      # Первая строка — каталог моделей (AI-INF-8). Остальное — AI-CMP-4: адрес инференса и
      # роль→модель пишутся в machine.d, не в dotfiles.
      systemd.tmpfiles.rules = [
        "d ${inference.modelsDir} 0750 ollama ollama - -"
      ]
      ++ lib.concatMap (user: [
        "L+ /home/${user}/.config/machine.d/ai-env - - - - ${pkgs.writeText "ai-env" ''
          # Сгенерировано Nix (inference-service-ollama, AI-CMP-4) — не редактируйте руками.
          export AI_INFERENCE_URL="http://${inference.host}:${toString inference.port}"
          export AI_MODEL_LOCAL_FAST="${roles.local-fast or ""}"
          export AI_MODEL_LOCAL_CHAT="${roles.local-chat or ""}"
        ''}"
      ]) config.my.host.users;

      # AI-INF-6: выгрузка до сна, перезапуск после — известный отказ Ollama
      # (после resume вычислительная библиотека теряет устройство GPU).
      systemd.services.inference-pre-sleep = {
        before = [ "sleep.target" ];
        wantedBy = [ "sleep.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${inferenceRelease}/bin/inference-release";
        };
      };

      systemd.services.inference-post-resume = {
        after = [
          "suspend.target"
          "hibernate.target"
          "hybrid-sleep.target"
          "suspend-then-hibernate.target"
        ];
        wantedBy = [
          "suspend.target"
          "hibernate.target"
          "hybrid-sleep.target"
          "suspend-then-hibernate.target"
        ];
        serviceConfig.Type = "oneshot";
        script = ''
          systemctl stop ollama.service
          ${pkgs.kmod}/bin/rmmod nvidia_uvm || true
          ${pkgs.kmod}/bin/modprobe nvidia_uvm
          systemctl start ollama.service
        '';
      };
    };
}
