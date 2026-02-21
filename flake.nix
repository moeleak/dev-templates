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

        typst = {
          path = ./templates/typst;
          description = "Typst environment.";
        };

        machine-learning = {
          path = ./templates/machine-learning;
          description = "A CUDA-enabled ML dev shell with uv.";
        };

      };
    };
}
