{
  description = "Project templates for dev environments";

  outputs =
    { self }:
    {
      templates = {
        rust = {
          path = ./templates/rust;
          description = "A Rust app.";
        };

        cpp = {
          path = ./templates/cpp;
          description = "A C++ app.";
        };

        typst = {
          path = ./templates/typst;
          description = "Typst environment.";
        };

        typst-slides = {
          path = ./templates/typst-slides;
          description = "Typst slides environment.";
        };

        machine-learning = {
          path = ./templates/machine-learning;
          description = "A CUDA-enabled ML dev shell with uv.";
        };

        machine-learning-uv2nix = {
          path = ./templates/machine-learning-uv2nix;
          description = "A CUDA/MPS-enabled ML dev shell with uv2nix.";
        };

      };
    };
}
