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

          nixglhost = nix-gl-host.defaultPackage.${system};
          linuxLibraryPath = lib.makeLibraryPath (
            fabricInputs
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

          cudaOverlay =
            final: previous:
            let
              nvidiaLibPath =
                name: component:
                lib.optional (lib.hasAttr name previous) "${final.${name}}/${python.sitePackages}/nvidia/${component}/lib";

              cublasPaths = nvidiaLibPath "nvidia-cublas" "cu13";
              cusparsePaths = nvidiaLibPath "nvidia-cusparse" "cu13";
              nvjitlinkPaths = nvidiaLibPath "nvidia-nvjitlink" "cu13";

              wheelLibraryPaths =
                cublasPaths
                ++ cusparsePaths
                ++ nvjitlinkPaths
                ++ nvidiaLibPath "nvidia-cuda-cupti" "cu13"
                ++ nvidiaLibPath "nvidia-cuda-nvrtc" "cu13"
                ++ nvidiaLibPath "nvidia-cuda-runtime" "cu13"
                ++ nvidiaLibPath "nvidia-cudnn-cu13" "cudnn"
                ++ nvidiaLibPath "nvidia-cufft" "cu13"
                ++ nvidiaLibPath "nvidia-cufile" "cu13"
                ++ nvidiaLibPath "nvidia-curand" "cu13"
                ++ nvidiaLibPath "nvidia-cusolver" "cu13"
                ++ nvidiaLibPath "nvidia-cusparselt-cu13" "cusparselt"
                ++ nvidiaLibPath "nvidia-nccl-cu13" "nccl"
                ++ nvidiaLibPath "nvidia-nvshmem-cu13" "nvshmem"
                ++ nvidiaLibPath "nvidia-nvtx" "cu13";
            in
            lib.optionalAttrs (lib.hasAttr "torch" previous) {
              torch = (addSearchPaths previous.torch wheelLibraryPaths).overrideAttrs (old: {
                autoPatchelfIgnoreMissingDeps = (old.autoPatchelfIgnoreMissingDeps or [ ]) ++ [
                  "libcuda.so.1"
                ];
              });
            }
            // patchIfPresent previous "nvidia-cufile" [
              pkgs.rdma-core
            ]
            // patchIfPresent previous "nvidia-nvshmem-cu13" fabricInputs
            // lib.optionalAttrs (lib.hasAttr "nvidia-cufft" previous) {
              nvidia-cufft = addSearchPaths previous.nvidia-cufft nvjitlinkPaths;
            }
            // lib.optionalAttrs (lib.hasAttr "nvidia-cusparse" previous) {
              nvidia-cusparse = addSearchPaths previous.nvidia-cusparse nvjitlinkPaths;
            }
            // lib.optionalAttrs (lib.hasAttr "nvidia-cusolver" previous) {
              nvidia-cusolver = addSearchPaths previous.nvidia-cusolver (
                cublasPaths ++ cusparsePaths ++ nvjitlinkPaths
              );
            }
            // lib.optionalAttrs (lib.hasAttr "nvidia-cudnn-cu13" previous) {
              nvidia-cudnn-cu13 = addSearchPaths previous.nvidia-cudnn-cu13 cublasPaths;
            };

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
          ++ lib.optional isLinux nixglhost;

          env = {
            UV_NO_SYNC = "1";
            UV_PYTHON = pythonSet.python.interpreter;
            UV_PYTHON_DOWNLOADS = "never";
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
