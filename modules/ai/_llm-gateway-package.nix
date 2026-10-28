# Приватная часть: llm-gateway · Владелец: modules/ai/llm-gateway.nix (STR-6)
# Пакет HTTP-транспорта Bifrost (AI-GW-13: из исходников, зафиксированная ревизия,
# без pip install/самообновления в рантайме). Деривация скопирована из собственного
# nix/packages/bifrost-http.nix апстрима (тег transports/v2.1.0 — первая версия,
# закрывающая CVE-2026-90898; CVE-2026-86242 закрыта раньше, в transports/v2.0.0) —
# не придумана: upstream уже даёт buildGoModule-рецепт, включая vendorHash для этой
# ревизии. Отличия от апстрима: без пакета bifrost-ui (отдельная JS-сборка веб-панели,
# свой npm-хэш) — панель нам не нужна (AI-GW-11 веб-подписку не обслуживает), поэтому
# постоянно используется их же запасной путь (пустая bifrost-http/ui/index.html).
# hash источника (fetchFromGitHub) — получен первой сборкой 2026-10-28, см. ниже.
# go_1_27 в стабильном канале 26.05 — ПРОВЕРИТЬ (go.mod требует 1.27.0); если нет —
# точечно из нестабильного канала (ARCH-14) под тем же именем атрибута.
{ pkgs, lib }:
let
  src = pkgs.fetchFromGitHub {
    owner = "maximhq";
    repo = "bifrost";
    rev = "transports/v2.1.0"; # ПРОВЕРИТЬ: актуальный тег ≥ этого на момент сборки
    hash = "sha256-Ln5eaUxoM0rjFetkJ+6hqEHv9rfti6BySKXvlWqYrOI="; # получено первой сборкой 2026-10-28
  };

  go = pkgs.go_1_27 or pkgs.go;
  buildGoModule = pkgs.buildGoModule.override { inherit go; };

  # Апстрим держит транспорт и внутренние модули (core, framework, plugins/*) как
  # отдельные go.mod в одном репозитории; go.work апстрима не публикуется с тегом,
  # поэтому локальные replace прописываются так же, как в их собственной деривации.
  localReplaces = ''
    if [ -f transports/go.mod ]; then
      cat >> transports/go.mod <<'EOF'

    replace github.com/maximhq/bifrost/core => ../core
    replace github.com/maximhq/bifrost/framework => ../framework
    replace github.com/maximhq/bifrost/plugins/governance => ../plugins/governance
    replace github.com/maximhq/bifrost/plugins/compat => ../plugins/compat
    replace github.com/maximhq/bifrost/plugins/logging => ../plugins/logging
    replace github.com/maximhq/bifrost/plugins/maxim => ../plugins/maxim
    replace github.com/maximhq/bifrost/plugins/otel => ../plugins/otel
    replace github.com/maximhq/bifrost/plugins/semanticcache => ../plugins/semanticcache
    replace github.com/maximhq/bifrost/plugins/telemetry => ../plugins/telemetry
    EOF
    fi
  '';
in
buildGoModule {
  pname = "bifrost-http";
  version = "2.1.0"; # ПРОВЕРИТЬ вместе с rev выше
  inherit src;

  modRoot = "transports";
  subPackages = [ "bifrost-http" ];
  # Хэш апстрима (их nix/packages/bifrost-http.nix) не совпал в нашей сборке —
  # видимо, из-за другой версии go/nixpkgs при резолве зависимостей; значение
  # ниже получено первой сборкой 2026-10-29. Пересчитать, если rev выше меняется.
  vendorHash = "sha256-6Mjlpz4CdIZcZsErfW7bXY6UR/ht7hcSTwTflhb7vW8=";

  doCheck = false;

  overrideModAttrs = _final: prev: {
    postPatch = (prev.postPatch or "") + localReplaces;
  };

  env.CGO_ENABLED = "1";
  nativeBuildInputs = [
    pkgs.pkg-config
    pkgs.gcc
  ];
  buildInputs = [ pkgs.sqlite ];

  postPatch = localReplaces;

  # go:embed all:ui в main.go — без веб-панели отдаём заглушку (AI-GW-11, см. шапку).
  preBuild = ''
    rm -rf bifrost-http/ui
    mkdir -p bifrost-http/ui
    printf '%s\n' '<!doctype html><meta charset="utf-8"><title>Bifrost</title>' > bifrost-http/ui/index.html
  '';

  ldflags = [
    "-s"
    "-w"
    "-X main.Version=2.1.0" # ПРОВЕРИТЬ вместе с version выше
  ];

  meta = {
    mainProgram = "bifrost-http";
    description = "llm-gateway (AI_SUBSYSTEM.md §3.3) — HTTP-транспорт Bifrost";
    homepage = "https://github.com/maximhq/bifrost";
    license = lib.licenses.asl20;
  };
}
