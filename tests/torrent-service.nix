# Проверка свойства (STRUCTURE 5.1): торрент-демон стартует с каталогами на томе данных
# вне снимков, слушает только loopback и пишет в них от своей учётной записи, оставаясь в
# песочнице. Конфиг этого не показывает: каталоги вне StateDirectory создаёт отдельный юнит
# nixpkgs, который сам никто не запускает, и служба молча падала со status=226/NAMESPACE.
# Обход туннеля по uid (ADR-43) проверяет tests/tunnel-m2.nix; здесь — только служба.
{
  pkgs,
  nixosModules,
  ...
}:
let
  n = nixosModules;
in
pkgs.testers.runNixOSTest {
  name = "torrent-service";

  nodes.machine = {
    imports = [
      n.host-facts
      n.net-facts
      n.torrent-transmission
    ];

    my.host = {
      name = "torrent-service-fixture";
      class = "vm";
      stateVersion = "26.05";
      users = [ ];
    };

    environment.systemPackages = [
      pkgs.curl
      pkgs.util-linux
    ];
  };

  testScript =
    { nodes, ... }:
    ''
      machine.wait_for_unit("transmission.service")

      root = "/var/lib/nosnapshot/torrents"

      with subtest("Каталоги загрузок на томе данных, владелец — служба, группа может писать"):
          assert machine.succeed(f"stat -c '%U:%G %a' {root}").strip() == "transmission:transmission 750"
          assert machine.succeed(f"stat -c '%U:%G %a' {root}/complete").strip() == "transmission:transmission 770"

      with subtest("RPC слушает только loopback и отвечает"):
          listen = machine.succeed("ss -ltn 'sport = :9091'")
          assert "127.0.0.1:9091" in listen and "0.0.0.0:9091" not in listen and "*:9091" not in listen, listen
          # 409 — штатный ответ Transmission без сессионного заголовка: сервис жив.
          assert machine.succeed("curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:9091/transmission/rpc").strip() == "409"

      with subtest("Запись в каталог загрузок из песочницы службы проходит"):
          pid = machine.succeed("systemctl show -p MainPID --value transmission.service").strip()
          uid = machine.succeed("id -u transmission").strip()
          gid = machine.succeed("id -g transmission").strip()
          machine.succeed(f"nsenter -t {pid} -m -S {uid} -G {gid} touch {root}/complete/probe")

      with subtest("Служба объявляет себя в my.net.bypass.users (ADR-43)"):
          assert ${builtins.toJSON nodes.machine.my.net.bypass.users} == ["transmission"]
    '';
}
