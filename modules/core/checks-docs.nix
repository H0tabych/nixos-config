# Сверка ID правил между документами docs/architecture/*.md и docs/adr/*.md
# (scripts/check-doc-ids.sh): ID, упомянутый в одном документе, должен быть
# определён хоть в одном. Отдельно от checks-structure.nix — та проверяет
# C1-C12 раздела 8 STRUCTURE.md (структуру repo), эта — согласованность
# самих нормативных документов.
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.doc-ids = pkgs.runCommand "check-doc-ids" { } ''
        cp -r ${self} src
        chmod -R u+w src
        cd src
        bash scripts/check-doc-ids.sh
        touch $out
      '';
    };
}
