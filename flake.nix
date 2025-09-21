{
  description = "Docling + CUDA dev shells";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forEachSystem = nixpkgs.lib.genAttrs systems;
  in {
    packages = forEachSystem (
      system: let
        overlayTorch = final: prev: let
          lib = prev.lib or nixpkgs.lib;
        in {
          python312Packages =
            prev.python312Packages
            // (lib.optionalAttrs (prev.python312Packages ? torch-bin) {
              torch = prev.python312Packages.torch-bin;
              torchvision = prev.python312Packages.torchvision-bin;
              torchaudio = prev.python312Packages.torchaudio-bin;
            });
        };

        # disable pytest for rapidocr-onnxruntime everywhere
        rapidocrNoCheckOverlay = final: prev: {
          python3Packages = prev.python3Packages.overrideScope (self: super: {
            "rapidocr-onnxruntime" = super."rapidocr-onnxruntime".overridePythonAttrs (_: {
              doCheck = false;
              nativeCheckInputs = [];
              checkPhase = "true";
            });
          });
          python312Packages = prev.python312Packages.overrideScope (self: super: {
            "rapidocr-onnxruntime" = super."rapidocr-onnxruntime".overridePythonAttrs (_: {
              doCheck = false;
              nativeCheckInputs = [];
              checkPhase = "true";
            });
          });
        };

        pkgsCuda = import nixpkgs {
          inherit system;
          overlays = [overlayTorch rapidocrNoCheckOverlay];
          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        };

        doclingEnv = pkgsCuda.python312.withPackages (ps:
          with ps; [
            docling
            docling-core
            docling-parse
            docling-ibm-models
            easyocr
            opencv4
            accelerate
            beautifulsoup4
            certifi
            filetype
            huggingface-hub
            numpy
            packaging
            pillow
            pydantic
            pypdf
            pyyaml
            requests
            scikit-image
            scipy
            shapely
            tiktoken
            tqdm
            typing-extensions
            torch
            torchvision
            torchaudio
          ]);
      in {
        doclingEnv = doclingEnv;
        default = doclingEnv;
      }
    );

    devShells = forEachSystem (
      system: let
        overlayTorch = final: prev: let
          lib = prev.lib or nixpkgs.lib;
        in {
          python312Packages =
            prev.python312Packages
            // (lib.optionalAttrs (prev.python312Packages ? torch-bin) {
              torch = prev.python312Packages.torch-bin;
              torchvision = prev.python312Packages.torchvision-bin;
              torchaudio = prev.python312Packages.torchaudio-bin;
            });
        };

        # disable pytest for rapidocr-onnxruntime everywhere
        rapidocrNoCheckOverlay = final: prev: {
          python3Packages = prev.python3Packages.overrideScope (self: super: {
            "rapidocr-onnxruntime" = super."rapidocr-onnxruntime".overridePythonAttrs (_: {
              doCheck = false;
              nativeCheckInputs = [];
              checkPhase = "true";
            });
          });
          python312Packages = prev.python312Packages.overrideScope (self: super: {
            "rapidocr-onnxruntime" = super."rapidocr-onnxruntime".overridePythonAttrs (_: {
              doCheck = false;
              nativeCheckInputs = [];
              checkPhase = "true";
            });
          });
        };

        pkgsCuda = import nixpkgs {
          inherit system;
          overlays = [overlayTorch rapidocrNoCheckOverlay];
          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        };

        doclingEnvCuda = pkgsCuda.python312.withPackages (ps:
          with ps; [
            docling
            docling-core
            docling-parse
            docling-ibm-models
            easyocr
            opencv4
            accelerate
            beautifulsoup4
            certifi
            filetype
            huggingface-hub
            numpy
            packaging
            pillow
            pydantic
            pypdf
            pyyaml
            requests
            scikit-image
            scipy
            shapely
            tiktoken
            tqdm
            typing-extensions
            torch
            torchvision
            torchaudio
          ]);

        cudaLibs = with pkgsCuda; [
          stdenv.cc.cc
          zlib
          libglvnd
          xorg.libX11
          xorg.libXext
          xorg.libXrender
          xorg.libXau
          xorg.libXdmcp
          cudaPackages.cudatoolkit
          cudaPackages.cudnn
          cudaPackages.nccl
        ];
      in {
        # CUDA shell
        default = pkgsCuda.mkShell {
          packages = [
            doclingEnvCuda
            pkgsCuda.cudaPackages.cudatoolkit
            pkgsCuda.cudaPackages.cudnn
            pkgsCuda.cudaPackages.nccl
          ];

          LD_LIBRARY_PATH = pkgsCuda.lib.makeLibraryPath cudaLibs;
          CUDA_PATH = pkgsCuda.cudaPackages.cudatoolkit;
          CUDA_HOME = pkgsCuda.cudaPackages.cudatoolkit;

          shellHook = ''
                        echo "CUDA dev shell ready — checking torch:"
                        python - <<'PY'
            import os, torch
            print("torch:", torch.__version__)
            print("CUDA available:", torch.cuda.is_available())
            print("torch.version.cuda:", torch.version.cuda)
            PY
          '';
        };

        # Explicit aliases
        cuda = self.devShells.${system}.default;
      }
    );

    formatter = forEachSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
      in
        pkgs.nixfmt-rfc-style
    );
  };
}
