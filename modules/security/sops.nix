# Фича: sops · Слот: — · Домен: security · Классы: N · Для: всех хостов
# Контракт: SEC-3, SEC-4, SEC-7, SEC-12. Подключает sops-nix. Ключ хоста
# берётся из SSH host ed25519-ключа по умолчанию sops-nix (sops.age.sshKeyPaths
# читает config.services.openssh.hostKeys, когда services.openssh.enable — так
# у нас уже есть через фичу ssh). Конкретные sops.secrets объявляют
# фичи-потребители (SEC-4), не эта фича.
# Зависимости: ssh (host ed25519-ключ для возраста хоста).
{ inputs, ... }:
{
  flake.modules.nixos.sops = {
    imports = [ inputs.sops-nix.nixosModules.sops ];
  };
}
