# Каркас: checks-structure · Домен: core
# Проверки структуры раздела 8 STRUCTURE.md. C1, C2, C4–C11 — в scripts/check-structure.sh
# (текстовые/find-проверки). C3 — здесь: нужен доступ к config.flake.modules.*, grep не годится.
{
  self,
  config,
  lib,
  ...
}:
let
  modulesDir = ../.;

  isFeatureDomain =
    name: type:
    type == "directory"
    && !(lib.hasPrefix "_" name)
    && !(builtins.elem name [
      "core"
      "users"
    ]);
  isFeatureFile =
    name: type: type == "regular" && lib.hasSuffix ".nix" name && !(lib.hasPrefix "_" name);

  featureDomains = builtins.attrNames (lib.filterAttrs isFeatureDomain (builtins.readDir modulesDir));

  featureFiles = lib.concatMap (
    domain:
    let
      files = builtins.attrNames (
        lib.filterAttrs isFeatureFile (builtins.readDir (modulesDir + "/${domain}"))
      );
    in
    map (file: {
      inherit domain file;
      name = lib.removeSuffix ".nix" file;
      path = "${domain}/${file}";
    }) files
  ) featureDomains;

  # STR-5: "# Фича: <имя> · Слот: <слот|—> · Домен: <домен> · Классы: <N|H|N+H> · Для: <адресат>"
  metadataRe = "# Фича: ([^ ]+) [^ ]+ Слот: [^ ]+ [^ ]+ Домен: ([^ ]+) [^ ]+ Классы: [^ ]+ [^ ]+ Для: .*";

  checkMetadata =
    ff:
    let
      firstLine = builtins.head (lib.splitString "\n" (builtins.readFile (modulesDir + "/${ff.path}")));
      m = builtins.match metadataRe firstLine;
    in
    if m == null then
      [ "modules/${ff.path}: первая строка не соответствует формату метаданных STR-5" ]
    else
      (lib.optional (
        builtins.elemAt m 0 != ff.name
      ) "modules/${ff.path}: имя в метаданных (${builtins.elemAt m 0}) не совпадает с путём")
      ++ (lib.optional (
        builtins.elemAt m 1 != ff.domain
      ) "modules/${ff.path}: домен в метаданных (${builtins.elemAt m 1}) не совпадает с путём");

  metadataErrors = lib.concatMap checkMetadata featureFiles;

  expectedNames = lib.unique (map (ff: ff.name) featureFiles);
  actualKeys = lib.unique (
    builtins.attrNames (config.flake.modules.nixos or { })
    ++ builtins.attrNames (config.flake.modules.homeManager or { })
  );

  keyErrors =
    (map (n: "файл modules/.../${n}.nix есть, но flake.modules.<класс>.${n} не определён (C3)") (
      builtins.filter (n: !(builtins.elem n actualKeys)) expectedNames
    ))
    ++ (map (n: "flake.modules.<класс>.${n} определён, но файла ${n}.nix в modules/ нет (C3)") (
      builtins.filter (n: !(builtins.elem n expectedNames)) actualKeys
    ));

  c3Errors = metadataErrors ++ keyErrors;
in
{
  perSystem =
    { pkgs, ... }:
    {
      checks.structure-shell = pkgs.runCommand "check-structure-shell" { } ''
        cp -r ${self} src
        chmod -R u+w src
        cd src
        bash scripts/check-structure.sh
        touch $out
      '';

      checks.structure-metadata =
        if c3Errors == [ ] then
          pkgs.runCommand "check-structure-metadata" { } "touch $out"
        else
          throw ("C3 (STR-5): найдены ошибки метаданных/ключей:\n- " + lib.concatStringsSep "\n- " c3Errors);
    };
}
