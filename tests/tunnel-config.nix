# Проверка свойства (STRUCTURE 5.1): конфиг клиента туннеля с фиктивными
# секретами корректного формата проходит проверку ядром Xray в обоих режимах
# (VPN-OPS-1, VPN-CLI-4); неверный формат ключа проверки выхода или короткого
# идентификатора ядро отклоняет (VPN-A14). Секреты не расшифровываются:
# config.sops.placeholder у sops-nix — чистая функция от имени секрета, подстановка
# фиктивных значений идёт по тексту плейсхолдера в уже отрисованном конфиге.
#
# M2 проверяется здесь же, в песочнице сборки: начиная с версий, где устройство
# создаётся при старте, а не при разборе конфига, `run -test` не требует
# CAP_NET_ADMIN (проверено на 26.10.31). На 26.3.27 он падал бы «operation not
# permitted»: при откате на неё проверку M2 нужно перенести в ВМ. Сам запуск с
# настоящими правами всё равно проверяет tests/tunnel-m2.nix.
{
  pkgs,
  lib,
  inputs,
  nixosModules,
  ...
}:
let
  n = nixosModules;

  mkTestHost =
    mode:
    inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        n.host-facts
        n.nix-settings
        n.sops
        n.tunnel-facts
        n.tunnel-xray
        {
          my.host = {
            name = "tunnel-config-fixture";
            class = "vm";
          };
          my.tunnel.mode = mode;
        }
      ];
    };

  m1Host = mkTestHost "m1";
  m2Host = mkTestHost "m2";

  fixtures = import ./fixtures/tunnel-xray.nix;

  render =
    host: values:
    lib.foldl' (
      acc: name: lib.replaceStrings [ host.config.sops.placeholder.${name} ] [ values.${name} ] acc
    ) host.config.sops.templates.tunnel-xray.content (builtins.attrNames values);

  writeConfig =
    host: name: values:
    pkgs.writeText "tunnel-xray-${name}.json" (render host (fixtures.valid // values));

  validConfig = writeConfig m1Host "valid" { };
  validM2Config = writeConfig m2Host "valid-m2" { };
  invalidKeyConfig = writeConfig m1Host "invalid-key" fixtures.invalidKey;
  invalidShortIdConfig = writeConfig m1Host "invalid-shortid" fixtures.invalidShortId;
in
pkgs.runCommand "tunnel-config"
  {
    # Тот же пакет, что у tunnel-xray: проверять надо ядром, которое будет работать.
    nativeBuildInputs = [ m1Host.pkgs.unstable.xray ];
  }
  ''
    echo "VPN-OPS-1: конфиг с фиктивными секретами корректного формата должен пройти проверку ядром"
    xray run -test -c ${validConfig}

    echo "VPN-OPS-1: то же для режима M2"
    xray run -test -c ${validM2Config}

    echo "VPN-A14: неверный ключ проверки выхода должен быть отклонён"
    if xray run -test -c ${invalidKeyConfig}; then
      echo "ожидался отказ ядра на неверном ключе" >&2
      exit 1
    fi

    echo "VPN-A14: неверный короткий идентификатор должен быть отклонён"
    if xray run -test -c ${invalidShortIdConfig}; then
      echo "ожидался отказ ядра на неверном shortId" >&2
      exit 1
    fi

    touch $out
  ''
