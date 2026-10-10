# Фича: ssh · Слот: — · Домен: security · Классы: N · Для: всех хостов
# Контракт: — (демон OpenSSH, ARCHITECTURE.md §6 — security).
# Зависимости: —
_: {
  flake.modules.nixos.ssh = _: {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
      # NET-11: порт открывает фича, которой он нужен — сейчас удалённый
      # доступ не востребован, порт остаётся закрытым до решения на хосте.
      openFirewall = false;
    };
  };
}
