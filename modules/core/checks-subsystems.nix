# Каркас: checks-subsystems · Домен: core
# Подключение tests/* (раздел 5.1 STRUCTURE.md): проверки поведения, которые
# нельзя выразить как `nix flake check` по формату (конфиг туннеля, killswitch,
# песочница агентов). Один файл tests/<свойство>.nix — одна проверка; это
# единственное место, где tests/*.nix подключаются (STRUCTURE 5.1).
{
  config,
  lib,
  inputs,
  ...
}:
let
  testsDir = ../../tests;

  isTestFile = name: type: type == "regular" && lib.hasSuffix ".nix" name;

  testFiles = builtins.attrNames (lib.filterAttrs isTestFile (builtins.readDir testsDir));
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks = lib.listToAttrs (
        map (
          file:
          lib.nameValuePair (lib.removeSuffix ".nix" file) (
            import (testsDir + "/${file}") {
              inherit pkgs lib inputs;
              nixosModules = config.flake.modules.nixos;
            }
          )
        ) testFiles
      );
    };
}
