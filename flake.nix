{
  description = "Docling + CUDA dev shells (uv2nix vendored deps)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # Added: uv2nix + friends for Python packaging via uv.lock
    pyproject-nix.url = "github:pyproject-nix/pyproject.nix";
    uv2nix.url = "github:pyproject-nix/uv2nix";
    pyproject-build-systems.url = "github:pyproject-nix/build-system-pkgs";

    # Keep inputs aligned with nixpkgs
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix.inputs.nixpkgs.follows = "nixpkgs";
    pyproject-build-systems.inputs.nixpkgs.follows = "nixpkgs";

    uv2nix.inputs.pyproject-nix.follows = "pyproject-nix";
    pyproject-build-systems.inputs.pyproject-nix.follows = "pyproject-nix";
  };

  outputs = {
    self,
    nixpkgs,
    pyproject-nix,
    uv2nix,
    pyproject-build-systems,
    ...
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

        # ---------------- uv2nix wiring (replaces python.withPackages) ----------------
        python = pkgsCuda.python312;

        # Reads pyproject.toml + uv.lock from repo root
        workspace = uv2nix.lib.workspace.loadWorkspace {
          workspaceRoot = ./.;
        };

        # Convert uv.lock into a pinned overlay of Python packages
        uvLockedOverlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel"; # switch to "sdist" if needed
        };

        # Compose Python pkg set with pyproject-nix + build systems + uv-locked deps
        pythonSet = (pkgsCuda.callPackage pyproject-nix.build.packages {inherit python;})
          .overrideScope (pkgsCuda.lib.composeManyExtensions [
          pyproject-build-systems.overlays.default
          uvLockedOverlay

          # Keep the rapidocr test-disable at python layer too (belt & suspenders)
          (final: prev: {
            "rapidocr-onnxruntime" = prev."rapidocr-onnxruntime".overridePythonAttrs (_: {
              doCheck = false;
              nativeCheckInputs = [];
              checkPhase = "true";
            });
          })
        ]);

        # Must match [project.name] in your pyproject.toml
        projectName = "docling";

        # Buildable wheel/sdist for your project
        doclingPkg = pythonSet.${projectName};

        # Reproducible virtualenv containing locked runtime deps
        doclingEnv = pythonSet.mkVirtualEnv (doclingPkg.pname + "-env") workspace.deps.default;
        # -----------------------------------------------------------------------
      in {
        # Keep your exports: env as a package + default
        doclingEnv = doclingEnv;
        default = doclingEnv;

        # Also expose the buildable package (wheel/sdist) if you want it:
        "${projectName}-pkg" = doclingPkg;
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

        # Recreate the same uv2nix env in devShell scope
        python = pkgsCuda.python312;
        workspace = uv2nix.lib.workspace.loadWorkspace {workspaceRoot = ./.;};
        uvLockedOverlay = workspace.mkPyprojectOverlay {sourcePreference = "wheel";};
        pythonSet = (pkgsCuda.callPackage pyproject-nix.build.packages {inherit python;})
          .overrideScope (pkgsCuda.lib.composeManyExtensions [
          pyproject-build-systems.overlays.default
          uvLockedOverlay
          (final: prev: {
            "rapidocr-onnxruntime" = prev."rapidocr-onnxruntime".overridePythonAttrs (_: {
              doCheck = false;
              nativeCheckInputs = [];
              checkPhase = "true";
            });
          })
        ]);
        projectName = "docling";
        doclingPkg = pythonSet.${projectName};
        doclingEnvCuda = pythonSet.mkVirtualEnv (doclingPkg.pname + "-env") workspace.deps.default;

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
        # CUDA shell (now using the uv2nix-built env instead of withPackages)
        default = pkgsCuda.mkShell {
          packages = [
            doclingEnvCuda
            pkgsCuda.cudaPackages.cudatoolkit
            pkgsCuda.cudaPackages.cudnn
            pkgsCuda.cudaPackages.nccl
            pkgsCuda.uv
            pkgsCuda.ruff
            pkgsCuda.pyright
          ];

          LD_LIBRARY_PATH = pkgsCuda.lib.makeLibraryPath cudaLibs;
          CUDA_PATH = pkgsCuda.cudaPackages.cudatoolkit;
          CUDA_HOME = pkgsCuda.cudaPackages.cudatoolkit;

          shellHook = ''
            echo "CUDA dev shell ready — checking torch (uv2nix env):"
            python - <<'PY'
            import os, torch
            print("torch:", torch.__version__)
            print("CUDA available:", torch.cuda.is_available())
            print("torch.version.cuda:", torch.version.cuda)
            PY

            echo
            echo "Tip:"
            echo "  • After changing deps: uv lock"
            echo "  • Prefetch/store deps: nix build .#doclingEnv"
          '';
        };

        # Explicit alias mirroring your original pattern
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
