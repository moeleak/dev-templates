{
  description = "Machine learning dev shell with uv and CUDA";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-gl-host.url = "github:moeleak/nix-gl-host";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nix-gl-host,
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        };

        packages = with pkgs; [
          cmake
          ninja
          cudaPackages.cudatoolkit
          cudaPackages.cuda_cudart
          cudaPackages.cuda_cupti
          cudaPackages.cuda_nvrtc
          cudaPackages.cuda_nvtx
          cudaPackages.cudnn
          cudaPackages.libcublas
          cudaPackages.libcufft
          cudaPackages.libcurand
          cudaPackages.libcusolver
          cudaPackages.libcusparse
          cudaPackages.libnvjitlink
          cudaPackages.nccl
          nix-gl-host.defaultPackage.${system}
          uv
          python312
          zlib
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          inherit packages;

          UV_DEFAULT_INDEX = "https://pypi.tuna.tsinghua.edu.cn/simple";

          shellHook = ''
            VENV_DIR=".venv"
            if [ ! -d "$VENV_DIR" ]; then
              uv venv
            fi
            source "$VENV_DIR/bin/activate"
            export LD_LIBRARY_PATH=$(nixglhost -p):$LD_LIBRARY_PATH
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath packages}:$LD_LIBRARY_PATH"
            export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:$LD_LIBRARY_PATH"
          '';
        };
      }
    );
}
