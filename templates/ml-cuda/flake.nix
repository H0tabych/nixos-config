{
  description = "ml-cuda: cudaPackages для sm_75, только кэшируемые бинарные сборки (A.5)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      # Отдельный импорт (не nixpkgs.legacyPackages): CUDA — unfree, и сборка
      # ограничена архитектурой хоста A.2 (GTX 1650, sm_75). cudaForwardCompat
      # выключен — без него собирается лишний PTX под будущие архитектуры,
      # не покрытый кэшем (AI-CC-2, "только кэшируемые бинарные сборки").
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          cudaSupport = true;
          cudaCapabilities = [ "7.5" ];
          cudaForwardCompat = false;
        };
      };
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.cudaPackages.cudatoolkit ];
      };
    };
}
