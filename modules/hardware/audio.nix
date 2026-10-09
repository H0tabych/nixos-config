# Фича: audio · Слот: — · Домен: hardware · Классы: N · Для: всех хостов
# Контракт: — (звуковой стек, ARCHITECTURE.md §6 — hardware).
# Зависимости: —
_: {
  flake.modules.nixos.audio = _: {
    security.rtkit.enable = true;

    services.pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
    };
  };
}
