{
  description = "Machine learning dev shell with uv2nix, PyTorch, CUDA, and MPS";

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
      forAllSystems = lib.genAttrs systems;

      workspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = ./.;
      };

      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      editableOverlay = workspace.mkEditablePyprojectOverlay {
        root = "$REPO_ROOT";
      };

      mkSystem =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
            };
          };

          python = pkgs.python312;
          isLinux = pkgs.stdenv.isLinux;
          nixglhost = nix-gl-host.defaultPackage.${system};

          runtimeLibraries =
            if isLinux then
              with pkgs;
              [
                libfabric
                openmpi
                pmix
                rdma-core
                stdenv.cc.cc.lib
                ucx
                zlib
              ]
            else
              [ ];

          libraryPath = lib.makeLibraryPath runtimeLibraries;
          setupLinuxLibraryPath = lib.optionalString isLinux ''
            host_library_path="$(nixglhost -p 2>/dev/null || true)"
            if [ -n "$host_library_path" ]; then
              export LD_LIBRARY_PATH="$host_library_path:${libraryPath}:''${LD_LIBRARY_PATH:-}"
            else
              export LD_LIBRARY_PATH="${libraryPath}:''${LD_LIBRARY_PATH:-}"
            fi
          '';

          addAutoPatchelfSearchPaths =
            paths:
            lib.concatMapStringsSep "\n" (
              path: "addAutoPatchelfSearchPath ${path}"
            ) paths;

          patchLibraryInputs =
            package: extraBuildInputs:
            package.overrideAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ extraBuildInputs;
            });

          patchSearchPaths =
            package: searchPaths:
            package.overrideAttrs (old: {
              preFixup =
                (old.preFixup or "")
                + lib.optionalString (searchPaths != [ ]) ''
                  ${addAutoPatchelfSearchPaths searchPaths}
                '';
            });

          patchPackage =
            previous: name: extraBuildInputs:
            lib.optionalAttrs (lib.hasAttr name previous) {
              ${name} = patchLibraryInputs previous.${name} extraBuildInputs;
            };

          patchPackageSearchPaths =
            previous: name: searchPaths:
            lib.optionalAttrs (lib.hasAttr name previous) {
              ${name} = patchSearchPaths previous.${name} searchPaths;
            };

          customOverlay =
            final: previous:
            let
              nvidiaLibPath =
                name: component:
                lib.optionals (lib.hasAttr name previous) [
                  "${final.${name}}/${python.sitePackages}/nvidia/${component}/lib"
                ];

              cudaToolkitLibPaths =
                nvidiaLibPath "nvidia-cublas" "cu13"
                ++ nvidiaLibPath "nvidia-cuda-cupti" "cu13"
                ++ nvidiaLibPath "nvidia-cuda-nvrtc" "cu13"
                ++ nvidiaLibPath "nvidia-cuda-runtime" "cu13"
                ++ nvidiaLibPath "nvidia-cudnn-cu12" "cudnn"
                ++ nvidiaLibPath "nvidia-cudnn-cu13" "cudnn"
                ++ nvidiaLibPath "nvidia-cufft" "cu13"
                ++ nvidiaLibPath "nvidia-cufile" "cu13"
                ++ nvidiaLibPath "nvidia-curand" "cu13"
                ++ nvidiaLibPath "nvidia-cusolver" "cu13"
                ++ nvidiaLibPath "nvidia-cusparse" "cu13"
                ++ nvidiaLibPath "nvidia-cusparselt-cu12" "cusparselt"
                ++ nvidiaLibPath "nvidia-cusparselt-cu13" "cusparselt"
                ++ nvidiaLibPath "nvidia-nccl-cu12" "nccl"
                ++ nvidiaLibPath "nvidia-nccl-cu13" "nccl"
                ++ nvidiaLibPath "nvidia-nvjitlink" "cu13"
                ++ nvidiaLibPath "nvidia-nvshmem-cu12" "nvshmem"
                ++ nvidiaLibPath "nvidia-nvshmem-cu13" "nvshmem"
                ++ nvidiaLibPath "nvidia-nvtx" "cu13";

              nvjitlinkPaths = nvidiaLibPath "nvidia-nvjitlink" "cu13";
              cublasPaths = nvidiaLibPath "nvidia-cublas" "cu13";
              cusparsePaths = nvidiaLibPath "nvidia-cusparse" "cu13";
            in
            {
              torch = previous.torch.overrideAttrs (old: {
                preFixup =
                  (old.preFixup or "")
                  + lib.optionalString (cudaToolkitLibPaths != [ ]) ''
                    ${addAutoPatchelfSearchPaths cudaToolkitLibPaths}
                  '';
                autoPatchelfIgnoreMissingDeps =
                  (old.autoPatchelfIgnoreMissingDeps or [ ])
                  ++ [
                    "libcuda.so.1"
                  ];
              });
            }
            // patchPackage previous "nvidia-cufile" [ pkgs.rdma-core ]
            // patchPackage previous "nvidia-cufile-cu12" [ pkgs.rdma-core ]
            // patchPackage previous "nvidia-cufile-cu13" [ pkgs.rdma-core ]
            // patchPackage previous "nvidia-nvshmem" [
              pkgs.libfabric
              pkgs.openmpi
              pkgs.pmix
              pkgs.rdma-core
              pkgs.ucx
            ]
            // patchPackage previous "nvidia-nvshmem-cu12" [
              pkgs.libfabric
              pkgs.openmpi
              pkgs.pmix
              pkgs.rdma-core
              pkgs.ucx
            ]
            // patchPackage previous "nvidia-nvshmem-cu13" [
              pkgs.libfabric
              pkgs.openmpi
              pkgs.pmix
              pkgs.rdma-core
              pkgs.ucx
            ]
            // patchPackageSearchPaths previous "nvidia-cudnn-cu12" cublasPaths
            // patchPackageSearchPaths previous "nvidia-cudnn-cu13" cublasPaths
            // patchPackageSearchPaths previous "nvidia-cufft" nvjitlinkPaths
            // patchPackageSearchPaths previous "nvidia-cusparse" nvjitlinkPaths
            // patchPackageSearchPaths previous "nvidia-cusparse-cu12" nvjitlinkPaths
            // patchPackageSearchPaths previous "nvidia-cusparse-cu13" nvjitlinkPaths
            // patchPackageSearchPaths previous "nvidia-cusolver" (
              cublasPaths ++ cusparsePaths ++ nvjitlinkPaths
            )
            // patchPackageSearchPaths previous "nvidia-cusolver-cu12" (
              cublasPaths ++ cusparsePaths ++ nvjitlinkPaths
            )
            // patchPackageSearchPaths previous "nvidia-cusolver-cu13" (
              cublasPaths ++ cusparsePaths ++ nvjitlinkPaths
            );

          pythonSet =
            (pkgs.callPackage pyproject-nix.build.packages {
              inherit python;
            }).overrideScope
              (
                lib.composeManyExtensions (
                  [
                    pyproject-build-systems.overlays.wheel
                    overlay
                  ]
                  ++ lib.optionals isLinux [
                    customOverlay
                  ]
                )
              );

          devPythonSet = pythonSet.overrideScope editableOverlay;
          virtualenv = pythonSet.mkVirtualEnv "machine-learning-uv2nix-env" workspace.deps.default;
          devVirtualenv = devPythonSet.mkVirtualEnv "machine-learning-uv2nix-dev-env" workspace.deps.all;

          torchDeviceCheck = pkgs.writeShellApplication {
            name = "torch-device-check";
            runtimeInputs =
              [
                virtualenv
              ]
              ++ lib.optionals isLinux [
                nixglhost
              ];
            text = ''
              ${setupLinuxLibraryPath}

              python - <<'PY'
              import warnings

              warnings.filterwarnings("ignore", message="Failed to initialize NumPy")

              import torch

              print(f"torch: {torch.__version__}")
              print(f"cuda available: {torch.cuda.is_available()}")
              print(f"cuda device count: {torch.cuda.device_count()}")
              if torch.cuda.is_available():
                  index = torch.cuda.current_device()
                  print(f"cuda current device: {index}")
                  print(f"cuda device name: {torch.cuda.get_device_name(index)}")

              mps = getattr(torch.backends, "mps", None)
              mps_built = bool(mps and mps.is_built())
              mps_available = bool(mps and mps.is_available())
              print(f"mps built: {mps_built}")
              print(f"mps available: {mps_available}")
              if mps_available:
                  device = torch.device("mps")
                  tensor = torch.ones(1, device=device)
                  print(f"mps device check: {tensor.device}")
              PY
            '';
          };

          cudaDeviceCheck = pkgs.writeShellApplication {
            name = "cuda-device-check";
            runtimeInputs = [
              torchDeviceCheck
            ];
            text = ''
              exec torch-device-check "$@"
            '';
          };
        in
        {
          packages = {
            default = virtualenv;
            cuda-device-check = cudaDeviceCheck;
            torch-device-check = torchDeviceCheck;
          };

          apps = rec {
            cuda-device-check = {
              type = "app";
              program = "${cudaDeviceCheck}/bin/cuda-device-check";
            };
            torch-device-check = {
              type = "app";
              program = "${torchDeviceCheck}/bin/torch-device-check";
            };
            default = torch-device-check;
          };

          devShells.default = pkgs.mkShell {
            packages =
              [
                cudaDeviceCheck
                devVirtualenv
                pkgs.uv
                torchDeviceCheck
              ]
              ++ lib.optionals isLinux [
                nixglhost
              ];

            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON = devPythonSet.python.interpreter;
              UV_PYTHON_DOWNLOADS = "never";
            };

            shellHook = ''
              unset PYTHONPATH
              export REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

              ${setupLinuxLibraryPath}
            '';
          };
        };

      perSystem = forAllSystems mkSystem;
    in
    {
      packages = lib.mapAttrs (_: systemOutput: systemOutput.packages) perSystem;
      apps = lib.mapAttrs (_: systemOutput: systemOutput.apps) perSystem;
      devShells = lib.mapAttrs (_: systemOutput: systemOutput.devShells) perSystem;
    };
}
