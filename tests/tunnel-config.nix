# Проверка свойства (STRUCTURE 5.1): конфиг клиента туннеля с фиктивными
# секретами корректного формата проходит проверку ядром Xray (VPN-OPS-1);
# неверный формат ключа проверки выхода или короткого идентификатора ядро
# отклоняет (VPN-A14). Секреты не расшифровываются: config.sops.placeholder
# у sops-nix — чистая функция от имени секрета, подстановка фиктивных
# значений идёт по тексту плейсхолдера в уже отрисованном конфиге.
{
  pkgs,
  lib,
  inputs,
  nixosModules,
  ...
}:
let
  n = nixosModules;

  testHost = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      n.host-facts
      n.sops
      n.tunnel-facts
      n.tunnel-xray
      {
        my.host = {
          name = "tunnel-config-fixture";
          class = "vm";
        };
      }
    ];
  };

  content = testHost.config.sops.templates.tunnel-xray.content;
  placeholder = name: testHost.config.sops.placeholder.${name};

  fixtures = import ./fixtures/tunnel-xray.nix;

  render =
    values:
    lib.foldl' (acc: name: lib.replaceStrings [ (placeholder name) ] [ values.${name} ] acc) content (
      builtins.attrNames values
    );

  writeConfig =
    name: values: pkgs.writeText "tunnel-xray-${name}.json" (render (fixtures.valid // values));

  validConfig = writeConfig "valid" { };
  invalidKeyConfig = writeConfig "invalid-key" fixtures.invalidKey;
  invalidShortIdConfig = writeConfig "invalid-shortid" fixtures.invalidShortId;
in
pkgs.runCommand "tunnel-config"
  {
    nativeBuildInputs = [ pkgs.xray ];
  }
  ''
    echo "VPN-OPS-1: конфиг с фиктивными секретами корректного формата должен пройти проверку ядром"
    xray run -test -c ${validConfig}

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
