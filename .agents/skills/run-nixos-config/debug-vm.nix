# Агентский тулинг (не часть флейка — import-tree сканирует только ./modules,
# этот файл ему не виден). Берёт штатный nixosConfigurations.ci-vm и
# накладывает ОДНУ отладочную настройку через extendModules, НЕ трогая
# modules/hosts/ci-vm.nix:
#   - services.getty.autologinUser = "root" — у ci-vm нет пользователей и
#     паролей (modules/hosts/ci-vm.nix: my.host.users = []), поэтому без
#     автологина в консоль попасть нечем. Это одноразовая тестовая ВМ,
#     никогда не разворачиваемая на реальном хосте — не секрет, не прод.
#
# virtualisation.graphics НЕ переопределяю здесь: этот option живёт внутри
# отдельно вычисляемого virtualisation.vmVariant (qemu-vm.nix в nixpkgs
# 26.05 строит systemd.build.vm через вложенный evalModules), и
# extendModules верхнего уровня его не видит ("option does not exist" —
# проверено). Вместо этого графика отключается на уровне запуска: сам
# сгенерированный скрипт run-nixos-vm дописывает "$QEMU_OPTS" "$@" в конец
# qemu-команды, поэтому достаточно передать `QEMU_OPTS=-nographic` при
# запуске (см. driver.sh) — без правки Nix-конфига.
#
# Сборка: nix build --impure -f debug-vm.nix -o <out>
# (--impure нужен из-за builtins.getFlake на локальном грязном git-дереве).
{
  flakeDir ? ../../..,
}:
let
  flake = builtins.getFlake (toString flakeDir);
in
(flake.nixosConfigurations.ci-vm.extendModules {
  modules = [ { services.getty.autologinUser = "root"; } ];
}).config.system.build.vm
