# Фича: compute-cache · Слот: — · Домен: ai · Классы: N · Для: хостов с GPU-вычислительным бэкендом
# Контракт: ML-2 (бинарный кэш вычислительной платформы подключён до сборки), AI-CC-1/2/3
# (AI_SUBSYSTEM.md §3.7, план этапа S1 — 8.4). Адрес и ключ — официальный кэш CUDA
# (wiki.nixos.org/wiki/CUDA, проверено 2026-10-25: предыдущий cuda-maintainers.cachix.org
# недействителен, HTTP 401). Покрытие стабильной ветки 26.05 — ПРОВЕРИТЬ `--dry-run`
# перед первой реальной сборкой (AI-CC-2/3, A.7 Архитектуры); на M1 кэш недостижим
# из-под nix-daemon (прокси не покрывает Nix, docs/runbook/tunnel.md, «Ограничения
# M1» — случай R8.1), переоценить после M2.
# Зависимости: host-facts (my.host.gpu.compute) — только чтение значения (ARCH-3).
_: {
  flake.modules.nixos.compute-cache =
    { config, lib, ... }:
    {
      nix.settings = lib.mkIf (config.my.host.gpu.compute == "cuda") {
        substituters = [ "https://cache.nixos-cuda.org" ];
        trusted-public-keys = [
          "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
        ];
      };
    };
}
