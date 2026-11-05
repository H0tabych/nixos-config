# Проверка свойства (STRUCTURE 5.1): каталог моделей инференса лежит на томе данных вне
# снимков (AI-INF-8), а сервис пишет в него от своей статической учётной записи, оставаясь
# в песочнице. Конфиг этого не показывает: при DynamicUser владелец каталога на другом томе
# заранее неизвестен, и сервис мог бы молча остаться без записи.
#
# Вычислительный бэкенд — `none` (процессор): проверяется путь и права, а не GPU, поэтому
# собирать CUDA-пакет не нужно. Записи в каталог сервис не делает сам (модели скачиваются
# отдельно), поэтому запись проверяется изнутри его пространства имён монтирования, от его
# пользователя: ровно так, как пишет сервис.
{
  pkgs,
  nixosModules,
  ...
}:
let
  n = nixosModules;
in
pkgs.testers.runNixOSTest {
  name = "inference-models-dir";

  nodes.machine = {
    imports = [
      n.host-facts
      n.ai-facts
      n.inference-service-ollama
    ];

    my.host = {
      name = "inference-models-dir-fixture";
      class = "vm";
      stateVersion = "26.05";
      gpu.compute = "none";
    };
    my.ai.inference.keepAlive = "5m";

    environment.systemPackages = [
      pkgs.curl
      pkgs.util-linux
    ];
  };

  testScript = ''
    machine.wait_for_unit("ollama.service")
    machine.wait_until_succeeds("curl -sf http://127.0.0.1:11434/api/tags")

    models = "/var/lib/nosnapshot/models"

    with subtest("AI-INF-8: каталог на томе данных, владелец — сервис, права закрыты"):
        assert machine.succeed(f"stat -c '%U:%G %a' {models}").strip() == "ollama:ollama 750"

    with subtest("Сервис работает от своей учётной записи, а не от случайной"):
        pid = machine.succeed("systemctl show -p MainPID --value ollama.service").strip()
        assert machine.succeed(f"ps -o user= -p {pid}").strip() == "ollama"
        uid = machine.succeed("id -u ollama").strip()
        gid = machine.succeed("id -g ollama").strip()

    with subtest("Запись в каталог моделей из песочницы сервиса проходит"):
        enter = f"nsenter -t {pid} -m -S {uid} -G {gid}"
        machine.succeed(f"{enter} touch {models}/probe")
        assert machine.succeed(f"stat -c '%U' {models}/probe").strip() == "ollama"

    with subtest("Остальной том данных из песочницы сервиса недоступен на запись"):
        machine.fail(f"{enter} touch /var/lib/nosnapshot/other")
  '';
}
