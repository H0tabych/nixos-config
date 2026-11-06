# Каркас: devshell · Домен: core
# Оболочка разработки репозитория (.envrc подключит её через `use flake`).
_: {
  perSystem =
    { config, pkgs, ... }:
    {
      devShells.default = pkgs.mkShellNoCC {
        packages = [
          pkgs.just
          pkgs.git
          pkgs.sops
          pkgs.age
          pkgs.nvd
          pkgs.gitleaks
          config.treefmt.build.wrapper
        ];
        # SEC-9: pre-commit сканер секретов лежит в scripts/git-hooks/, включает
        # его `just hooks`. shellHook не пишет в .git/config (AI-SBX-7).
      };
    };
}
