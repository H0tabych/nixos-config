{
  description = "cpp: clang/gcc, cmake, ninja, ccache, gdb, lldb (A.5)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.clang
          pkgs.gcc
          pkgs.cmake
          pkgs.ninja
          pkgs.ccache
          pkgs.gdb
          pkgs.lldb
        ];
      };
    };
}
