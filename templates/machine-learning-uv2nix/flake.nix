{
  description = "Machine learning dev shell with uv2nix, CUDA, and MPS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-gl-host.url = "github:moeleak/nix-gl-host";
  };

  outputs =
    {
      nixpkgs,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      nix-gl-host,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      workspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = ./.;
      };

      baseOverlays = [
        pyproject-build-systems.overlays.wheel
        (workspace.mkPyprojectOverlay {
          sourcePreference = "wheel";
        })
      ];

      editableOverlay = workspace.mkEditablePyprojectOverlay {
        root = "$REPO_ROOT";
      };

      mkDevShell =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          python = pkgs.python312;
          isLinux = pkgs.stdenv.isLinux;
          isDarwin = pkgs.stdenv.isDarwin;

          fabricInputs = with pkgs; [
            libfabric
            openmpi
            pmix
            rdma-core
            ucx
          ];

          cudaToolkit = pkgs.cudaPackages.cudatoolkit;

          nixglhost = nix-gl-host.defaultPackage.${system};
          linuxLibraryPath = lib.makeLibraryPath (
            fabricInputs
            ++ [
              cudaToolkit
            ]
            ++ [
              pkgs.stdenv.cc.cc.lib
              pkgs.zlib
            ]
          );

          setupLinuxLibraryPath = lib.optionalString isLinux ''
            host_library_path="$(${nixglhost}/bin/nixglhost -p 2>/dev/null || true)"
            export LD_LIBRARY_PATH="${linuxLibraryPath}:''${LD_LIBRARY_PATH:-}"
            if [ -n "$host_library_path" ]; then
              export LD_LIBRARY_PATH="$host_library_path:$LD_LIBRARY_PATH"
            fi
          '';

          addBuildInputs =
            package: inputs:
            package.overrideAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ inputs;
            });

          addSearchPaths =
            package: paths:
            package.overrideAttrs (old: {
              preFixup =
                (old.preFixup or "")
                + lib.optionalString (paths != [ ]) ''
                  ${lib.concatMapStringsSep "\n" (path: "addAutoPatchelfSearchPath ${path}") paths}
                '';
            });

          patchIfPresent =
            previous: name: inputs:
            lib.optionalAttrs (lib.hasAttr name previous) {
              ${name} = addBuildInputs previous.${name} inputs;
            };

          patchSearchPathsIfPresent =
            previous: name: paths:
            lib.optionalAttrs (lib.hasAttr name previous) {
              ${name} = addSearchPaths previous.${name} paths;
            };

          cudaOverlay =
            final: previous:
            let
              cudaPackageNames =
                base: [
                  base
                  "${base}-cu12"
                  "${base}-cu13"
                ];

              nvidiaPackagePaths =
                names:
                lib.concatMap (
                  name:
                  lib.optional (lib.hasAttr name previous) "${final.${name}}/${python.sitePackages}"
                ) names;

              patchBuildInputs =
                names: inputs:
                lib.foldl' (attrs: name: attrs // patchIfPresent previous name inputs) { } names;

              patchSearchPaths =
                names: paths:
                lib.foldl' (attrs: name: attrs // patchSearchPathsIfPresent previous name paths) { } names;

              cublasNames = cudaPackageNames "nvidia-cublas";
              cudaCuptiNames = cudaPackageNames "nvidia-cuda-cupti";
              cudaNvrtcNames = cudaPackageNames "nvidia-cuda-nvrtc";
              cudaRuntimeNames = cudaPackageNames "nvidia-cuda-runtime";
              cudnnNames = cudaPackageNames "nvidia-cudnn";
              cufftNames = cudaPackageNames "nvidia-cufft";
              cufileNames = cudaPackageNames "nvidia-cufile";
              curandNames = cudaPackageNames "nvidia-curand";
              cusolverNames = cudaPackageNames "nvidia-cusolver";
              cusparseNames = cudaPackageNames "nvidia-cusparse";
              cusparseltNames = cudaPackageNames "nvidia-cusparselt";
              ncclNames = cudaPackageNames "nvidia-nccl";
              nvjitlinkNames = cudaPackageNames "nvidia-nvjitlink";
              nvshmemNames = cudaPackageNames "nvidia-nvshmem";
              nvtxNames = cudaPackageNames "nvidia-nvtx";

              cublasPaths = nvidiaPackagePaths cublasNames;
              cusparsePaths = nvidiaPackagePaths cusparseNames;
              nvjitlinkPaths = nvidiaPackagePaths nvjitlinkNames;

              wheelLibraryPaths =
                cublasPaths
                ++ cusparsePaths
                ++ nvjitlinkPaths
                ++ nvidiaPackagePaths cudaCuptiNames
                ++ nvidiaPackagePaths cudaNvrtcNames
                ++ nvidiaPackagePaths cudaRuntimeNames
                ++ nvidiaPackagePaths cudnnNames
                ++ nvidiaPackagePaths cufftNames
                ++ nvidiaPackagePaths cufileNames
                ++ nvidiaPackagePaths curandNames
                ++ nvidiaPackagePaths cusolverNames
                ++ nvidiaPackagePaths cusparseltNames
                ++ nvidiaPackagePaths ncclNames
                ++ nvidiaPackagePaths nvshmemNames
                ++ nvidiaPackagePaths nvtxNames;
            in
            lib.optionalAttrs (lib.hasAttr "torch" previous) {
              torch = (addSearchPaths previous.torch wheelLibraryPaths).overrideAttrs (old: {
                autoPatchelfIgnoreMissingDeps = (old.autoPatchelfIgnoreMissingDeps or [ ]) ++ [
                  "libcuda.so.1"
                ];
              });
            }
            // patchBuildInputs cufileNames [
              pkgs.rdma-core
            ]
            // patchBuildInputs nvshmemNames fabricInputs
            // patchSearchPaths cufftNames nvjitlinkPaths
            // patchSearchPaths cusparseNames nvjitlinkPaths
            // patchSearchPaths cusolverNames (
              cublasPaths ++ cusparsePaths ++ nvjitlinkPaths
            )
            // patchSearchPaths cudnnNames cublasPaths;

          pythonSet =
            (pkgs.callPackage pyproject-nix.build.packages {
              inherit python;
            }).overrideScope
              (
                lib.composeManyExtensions (
                  baseOverlays
                  ++ lib.optional isLinux cudaOverlay
                  ++ [
                    editableOverlay
                  ]
                )
              );

          virtualenv = pythonSet.mkVirtualEnv "machine-learning-uv2nix-dev" workspace.deps.all;
        in
        pkgs.mkShell {
          packages = [
            virtualenv
            pkgs.uv
          ]
          ++ lib.optionals isLinux [
            cudaToolkit
            nixglhost
          ];

          env = {
            UV_NO_SYNC = "1";
            UV_PYTHON = pythonSet.python.interpreter;
            UV_PYTHON_DOWNLOADS = "never";
          }
          // lib.optionalAttrs isLinux {
            CUDA_HOME = cudaToolkit;
            CUDA_PATH = cudaToolkit;
          }
          // lib.optionalAttrs isDarwin {
            PYTORCH_ENABLE_MPS_FALLBACK = "1";
          };

          shellHook = ''
            unset PYTHONPATH
            export REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

            ${setupLinuxLibraryPath}
          '';
        };
    in
    {
      devShells = lib.genAttrs systems (system: {
        default = mkDevShell system;
      });
    };
}
