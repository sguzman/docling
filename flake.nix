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
    packages = forEachSystem (system: let
      pkgsCuda = import nixpkgs {
        inherit system;
        overlays = [rapidocrNoCheckOverlay]; # no overlayTorch here
        config = {
          allowUnfree = true;
          cudaSupport = true;
        };
      };
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
      doclingEnv = pythonSet.mkVirtualEnv (doclingPkg.pname + "-env") {
        groups = ["default"];
        extras = [];
      };
    in {
      doclingEnv = doclingEnv;
      default = doclingEnv;
      "${projectName}-pkg" = doclingPkg;
    });

    devShells = forEachSystem (
      system: let
        # KEEP: your rapidocr overlay; DROP overlayTorch from the uv2nix build path
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
          overlays = [rapidocrNoCheckOverlay]; # <-- dropped overlayTorch here
          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        };

        # uv2nix env (same as before, BUT built without overlayTorch interfering)
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
        doclingEnvCuda = pythonSet.mkVirtualEnv (doclingPkg.pname + "-env") {
          groups = ["default"];
          extras = [];
        };

        # Bring CUDA-enabled torch at SHELL layer (not inside uv graph)
        torchBin = pkgsCuda.python312Packages.torch-bin;
        torchvisionBin = pkgsCuda.python312Packages.torchvision-bin;
        torchaudioBin = pkgsCuda.python312Packages.torchaudio-bin;

        # Site-packages paths to compose PYTHONPATH
        pyVer = pkgsCuda.python312.lib.pythonVersion; # e.g. "3.12"
        site = p: "${p}/lib/python${pyVer}/site-packages";

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
        default = pkgsCuda.mkShell {
          packages = [
            doclingEnvCuda
            pkgsCuda.cudaPackages.cudatoolkit
            pkgsCuda.cudaPackages.cudnn
            pkgsCuda.cudaPackages.nccl
            torchBin
            torchvisionBin
            torchaudioBin
            pkgsCuda.uv
            pkgsCuda.ruff
            pkgsCuda.pyright
          ];

          # Make uv2nix venv see CUDA torch
          PYTHONPATH = pkgsCuda.lib.makeSearchPath "lib/python${pyVer}/site-packages" [
            (site doclingEnvCuda)
            (site torchBin)
            (site torchvisionBin)
            (site torchaudioBin)
          ];

          LD_LIBRARY_PATH = pkgsCuda.lib.makeLibraryPath cudaLibs;
          CUDA_PATH = pkgsCuda.cudaPackages.cudatoolkit;
          CUDA_HOME = pkgsCuda.cudaPackages.cudatoolkit;

          shellHook = ''
                    echo "CUDA dev shell — checking torch (uv env + torch-bin on PYTHONPATH):"
                    python - <<'PY'
            import sys, torch
            print("python:", sys.version.split()[0])
            print("torch:", torch.__version__)
            print("CUDA available:", torch.cuda.is_available())
            print("torch.version.cuda:", torch.version.cuda)
            PY
          '';
        };

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
