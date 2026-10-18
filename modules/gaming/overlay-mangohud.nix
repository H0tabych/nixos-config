# Фича: overlay-mangohud · Слот: overlay · Домен: gaming · Классы: H · Для: capability gaming
# Контракт: A.3 (слот overlay → MangoHud). Только пакет: конфиг — из реестра
# dotfiles (DOT-3, SLOT-1), генерируется theme/gen/gen.py (DSN-CMP-20);
# programs.mangohud (HM) здесь не используется — он сам пишет MangoHud.conf
# и столкнулся бы с симлинком dotfiles на тот же путь.
# Зависимости: —
_: {
  flake.modules.homeManager.overlay-mangohud =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.mangohud ];
    };
}
