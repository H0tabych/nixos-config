# Проверка свойства (STRUCTURE 5.1): конфиг клиента туннеля в режиме M2
# (tun-in, dns-out, domainStrategy AsIs, sockopt.mark) проходит проверку
# ядром Xray (VPN-OPS-1), как и M1-вариант в tests/tunnel-config.nix.
#
# Почему не pkgs.runCommand, как у M1-теста. Там хватает песочницы nix build:
# socks-in/http-in не трогают сеть хоста. tun-in при валидации РЕАЛЬНО
# пытается создать устройство — проверено вручную на пакете из этого flake:
# без CAP_NET_ADMIN `xray run -test` падает "operation not permitted", а не
# ошибкой синтаксиса. Песочница `nix build` такой capability никогда не
# даёт, поэтому проверка — в ВМ (как tests/killswitch-fail-fast.nix), где у
# testScript она есть, ровно как у настоящего tunnel-xray.service (M2
# выставляет AmbientCapabilities = [ "CAP_NET_ADMIN" ]).
#
# Рендер конфига — на этапе eval (та же техника, что у M1-теста: фиктивные
# значения из fixtures/tunnel-xray.nix подставляются в уже отрисованный
# sops.templates.tunnel-xray.content по тексту плейсхолдера, без
# расшифровки секретов). Сам узел ВМ минимальный — только pkgs.xray,
# tunnel-xray туда не подключается: иначе понадобились бы настоящие
# sops-ключи для активации сервиса, а здесь проверяется только то, что
# ядро принимает отрисованный JSON с реальными правами.
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
          name = "tunnel-config-m2-fixture";
          class = "vm";
        };
        my.tunnel.mode = "m2";
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

  validConfig = pkgs.writeText "tunnel-xray-m2.json" (render fixtures.valid);
in
pkgs.testers.runNixOSTest {
  name = "tunnel-config-m2";

  nodes.machine = {
    environment.systemPackages = [ pkgs.xray ];
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # VPN-OPS-1 в M2: с реальным CAP_NET_ADMIN (root в ВМ) tun-in должен
    # пройти дальше синтаксиса — до попытки создать устройство и настроить
    # маршруты. Без привилегии это падает с "operation not permitted"
    # (проверено вручную); здесь привилегия есть, поэтому отказа быть не должно.
    machine.succeed("xray run -test -c ${validConfig}")
  '';
}
