# Каркас: devshell · Домен: core
# Оболочка разработки репозитория (.envrc подключит её через `use flake`).
_: {
  perSystem =
    { config, pkgs, ... }:
    {
      devShells.default = pkgs.mkShellNoCC {
        packages = [
          pkgs.just
          pkgs.sops
          pkgs.age
          pkgs.nvd
          pkgs.gitleaks
          config.treefmt.build.wrapper
        ];
      };
    };
}
