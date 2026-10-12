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
        # SEC-9: pre-commit сканер секретов — хук лежит в scripts/git-hooks/.
        shellHook = ''
          git config core.hooksPath scripts/git-hooks
        '';
      };
    };
}
