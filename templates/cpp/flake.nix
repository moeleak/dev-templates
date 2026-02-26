{
  description = "A C++ app.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        cppPkgs = with pkgs; [
          # add cpp pkgs here
        ];

        toolchain = with pkgs; [
          clang-tools
          llvm
          clang
          cmake
          cppcheck
          pkg-config
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          packages = toolchain ++ cppPkgs;
          shellHook = ''
            build_dir="build"
            mkdir -p "$build_dir"
            cmake -S . -B "$build_dir" -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON >/dev/null 2>&1 || true
            if [ -f "$build_dir/compile_commands.json" ]; then
              ln -sf "$build_dir/compile_commands.json" compile_commands.json
            fi
          '';
        };

        packages = {
          default = pkgs.stdenv.mkDerivation {
            pname = "cpp-app";
            version = "0.1.0";
            src = ./.;
            nativeBuildInputs = with pkgs; [
              cmake
              ninja
            ];
            buildInputs = cppPkgs;
          };
        };
      }
    );
}
