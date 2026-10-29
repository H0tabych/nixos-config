# Приватная часть: agents-tools · Владелец: modules/ai/agents-tools.nix (STR-6)
# DeepSeek Harness (`dsh`, роль «альтернативный автономный», AI-AGT-1) не
# опубликован в nixpkgs (ПРОВЕРЕНО `nix eval` 2026-10-29: нет ни в 26.05, ни в
# unstable). Сам репозиторий deepseek-ai/deepseek-harness — монорепозиторий на
# 70+ pnpm-workspace-пакетов со своим сборщиком (apps/desktop на Electron,
# нативные macOS CUA-драйверы) — пересобирать его целиком не нужно: нужный нам
# CLI (apps/cli, пакет @deepseek-ai/dsh) публикуется в npm-реестр отдельно, с
# обычными (не workspace:*) диапазонами версий на все свои транзитивные
# зависимости (ПРОВЕРЕНО: `npm install` резолвит дерево целиком с
# registry.npmjs.org, без монорепозитория). Это тот же путь, которым CLI
# ставят все («npm install -g @deepseek-ai/dsh») — оформленный как обычная
# Nix-деривация, по приёму AI-CTX-5 («нет в канале — вход с зафиксированной
# ревизией», тот же общий принцип, что у приватного пакета Bifrost в фиче
# llm-gateway, STR-6, только npm вместо Go-модулей).
#
# _agents-tools-dsh-package.json/-package-lock.json рядом — не фича и не
# генерируются: минимальный синтетический проект («зависимость на
# @deepseek-ai/dsh нужной версии») с committed-лок-файлом. npm-эквивалент
# vendorHash — npmDepsHash. Обновление версии: поднять версию в
# _agents-tools-dsh-package.json, пересчитать _agents-tools-dsh-package-lock.json
# (`npm install --package-lock-only`) и npmDepsHash
# (`prefetch-npm-deps package-lock.json`) — ПРОВЕРЕНО этой же процедурой
# 2026-10-29.
#
# Нативные зависимости (`node-pty` — псевдотерминал для интерактивного режима,
# `koffi`/`sharp`/`sherpa-onnx` — FFI/изображения/голос) ставятся из готовых
# npm-пакетов-пребилдов на платформу (пакеты вида `<имя>-linux-x64`) —
# компиляции на лету нет; ПРОВЕРЕНО реальной сборкой 2026-10-29 (`fixupPhase`
# только поправил RPATH уже готовых `.node`-бинарников).
#
# Замена на nixpkgs одной правкой — см. agents-tools.nix:
# `pkgs.unstable.deepseek-harness or (pkgs.callPackage ./_agents-tools-dsh-package.nix {})`.
# Перед каждым `flake update` проверять `nix search nixpkgs deepseek-harness` —
# как только пакет появится в канале, этот файл и обе JSON-заготовки рядом
# можно удалить.
#
# ВРЕМЕННЫЙ ОБХОД, снимается по условию ниже. `dsh` не запускается на Node из
# nixpkgs: его зависимость `node-addon-require-builtin` — нативный аддон,
# который ищет внутренние акцессоры V8 сканированием машинного кода, и на
# сборке Node из nixpkgs шаблон не находится
# («Unsupported/no-getter: x64 sysv getter is not a recognized this->field
# accessor»). ПРОВЕРЕНО 2026-10-29: падает на nodejs_24 24.21.0 и в 26.05, и в
# unstable; с ОФИЦИАЛЬНЫМ бинарником Node той же версии (nodejs.org, только
# autoPatchelfHook, без FHS-обёртки) аддон загружается, и `dsh --profile
# headless` поднимается полностью. Исходников аддона в npm-пакете нет (только
# один пребилд `napi-v9`), поэтому пересобрать его под нашу сборку Node нельзя.
# Поэтому `dsh` — и только он — запускается официальным Node; системный
# `nodejs` не подменяется (ARCH-5: политика пакетов остаётся одна).
# КАК СНЯТЬ: проверить одной командой, что аддон заработал на Node из nixpkgs —
#   nix shell nixpkgs#nodejs --command node -e \
#     'require("<store-path-dsh>/lib/node_modules/dsh-pin/node_modules/node-addon-require-builtin/lib/index.js").requireBuiltin("internal/modules/esm/loader")'
# — и если да (апстрим починил аддон, либо пакет пришёл из nixpkgs), удалить
# `nodeOfficial` и `nodejs = nodeOfficial` ниже. Версия официального Node
# закреплена хэшем и обновляется осознанно, автообновления нет.
{ pkgs, lib }:
let
  # Версия намеренно совпадает с pkgs.nodejs_24 (24.21.0): обход касается
  # только способа сборки бинарника, не версии рантайма.
  nodeOfficial = pkgs.stdenv.mkDerivation {
    pname = "nodejs-official";
    version = "24.21.0"; # держать равной pkgs.nodejs_24.version; ПРОВЕРИТЬ при обновлении канала
    src = pkgs.fetchurl {
      url = "https://nodejs.org/dist/v24.21.0/node-v24.21.0-linux-x64.tar.xz";
      hash = "sha256-/Y5Z1aURUQ9qKYr7VI8Yx9KxvkBNi0on2U++SfVsstY="; # получено первой сборкой 2026-10-29
    };
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [
      pkgs.stdenv.cc.cc.lib
      pkgs.zlib
    ];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r . "$out"
      runHook postInstall
    '';
    meta = {
      mainProgram = "node";
      # buildNpmPackage читает nodejs.meta.platforms (build-npm-package/default.nix).
      platforms = [ "x86_64-linux" ]; # официальный тарбол выше — только linux-x64
    };
  };
in
pkgs.buildNpmPackage {
  pname = "deepseek-harness";
  version = "0.2.1-rc.2"; # npm dist-tag `latest` на 2026-10-29; dev preview, без стабильных релизов — ПРОВЕРИТЬ при обновлении
  src = pkgs.runCommand "agents-tools-dsh-src" { } ''
    mkdir -p "$out"
    cp ${./_agents-tools-dsh-package.json} "$out/package.json"
    cp ${./_agents-tools-dsh-package-lock.json} "$out/package-lock.json"
  '';
  npmDepsHash = "sha256-DwhtIOsfyalMTbgWY2iftdT6fG6J77mtxGK2anp+P5A="; # prefetch-npm-deps, 2026-10-29
  dontNpmBuild = true; # пакет публикуется уже собранным (lib/*.js) — компилировать нечего

  # Обход выше касается только ЗАПУСКА. Собирать официальным Node нельзя: его
  # `npm` имеет шебанг /usr/bin/env, которого нет в сборочной песочнице
  # (ПРОВЕРЕНО: "bad interpreter"). Поэтому зависимости ставит обычный
  # pkgs.nodejs, а в готовой обёртке `bin/dsh` путь к рантайму подменяется на
  # официальный — замена точная (--replace-fail), поэтому молча не разъедется.
  postFixup = ''
    substituteInPlace "$out/bin/dsh" \
      --replace-fail "${pkgs.nodejs}/bin/node" "${nodeOfficial}/bin/node"
  '';

  meta = {
    mainProgram = "dsh";
    description = "agents-tools (AI_SUBSYSTEM.md §3.4) — DeepSeek Harness, роль «альтернативный автономный» (AI-AGT-1)";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = lib.licenses.mit;
  };
}
