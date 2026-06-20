{
  description = "OpenViking: from-source build and wheel-based dev overlay.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        python = pkgs.python313;
        ps = python.pkgs;

        # ---------- Python deps not in nixpkgs ----------

        json-repair = ps.buildPythonPackage rec {
          pname = "json-repair";
          version = "0.59.2";
          format = "pyproject";
          src = ps.fetchPypi {
            pname = "json_repair";
            inherit version;
            sha256 = "0gcb4wdx7kw1wxnkwn4wy3ffib2xg2ijx2grdsk3ah2cm4pvp2hx";
          };
          buildInputs = [ ps.setuptools ];
          propagatedBuildInputs = [ ps.jsonschema ps.pydantic ];
          doCheck = false;
        };

        volcengine = ps.buildPythonPackage rec {
          pname = "volcengine";
          version = "1.0.219";
          format = "setuptools";
          src = ps.fetchPypi {
            inherit pname version;
            sha256 = "0hlrnkd2qr8gl5cbvfa6ki2j6vkp4d953l1khhknb2f3sgww8vvq";
          };
          propagatedBuildInputs = [
            ps.google ps.protobuf ps.pycryptodome ps.pytz
            ps.requests ps.retry ps.six
          ];
          doCheck = false;
          pythonImportsCheck = [ ];
        };

        volcengine-python-sdk = ps.buildPythonPackage rec {
          pname = "volcengine-python-sdk";
          version = "5.0.23";
          format = "setuptools";
          src = ps.fetchPypi {
            pname = "volcengine_python_sdk";
            inherit version;
            sha256 = "1sspky73cvj9brvvfdmgpnkzq4pz5d7nvxwi0n19kvr3ixnzx4jx";
          };
          propagatedBuildInputs = [ ps.certifi ps.python-dateutil ps.six ps.urllib3 ];
          doCheck = false;
          pythonImportsCheck = [ ];
        };

        lark-oapi = ps.buildPythonPackage rec {
          pname = "lark-oapi";
          version = "1.5.3";
          format = "wheel";
          src = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/bf/ff/2ece5d735ebfa2af600a53176f2636ae47af2bf934e08effab64f0d1e047/lark_oapi-1.5.3-py3-none-any.whl";
            sha256 = "0dnc40z4nkm5cggdlnlq3r97qk5r0337jjg9mayvc8cdncmv79px";
          };
          propagatedBuildInputs = [
            ps.requests ps.requests-toolbelt ps.pycryptodome
            ps.websockets ps.httpx
          ];
          doCheck = false;
        };

        opentelemetry-instrumentation-asyncio = ps.buildPythonPackage rec {
          pname = "opentelemetry-instrumentation-asyncio";
          version = "0.62b0";
          format = "pyproject";
          src = ps.fetchPypi {
            pname = "opentelemetry_instrumentation_asyncio";
            inherit version;
            sha256 = "14wiphzxzb2y969fpw8gi26ap03xx99zb84dfaz3ynadhmp1pbad";
          };
          buildInputs = [ ps.hatchling ];
          propagatedBuildInputs = [
            ps.opentelemetry-api ps.opentelemetry-instrumentation
            ps.opentelemetry-semantic-conventions ps.wrapt
          ];
          nativeBuildInputs = [ ps.pythonRelaxDepsHook ];
          pythonRelaxDeps = true;
          doCheck = false;
        };

        # Runtime Python deps shared by both package variants and the dev shell.
        runtimeDeps = [
          ps.pydantic ps.typing-extensions ps.pyyaml ps.httpx ps.pdfplumber
          ps.readabilipy ps.markdownify ps.openai ps.requests ps.python-docx
          ps.olefile ps.xlrd ps.python-pptx ps.openpyxl ps.ebooklib
          json-repair ps.apscheduler volcengine volcengine-python-sdk
          ps.fastapi ps.uvicorn ps.xxhash ps.jinja2 ps.tabulate ps.urllib3
          ps.protobuf ps.pdfminer-six ps.typer ps.litellm ps.python-multipart
          ps.tree-sitter ps.tree-sitter-python ps.tree-sitter-javascript
          ps.tree-sitter-rust ps.tree-sitter-c-sharp ps.opentelemetry-api
          ps.opentelemetry-sdk ps.opentelemetry-exporter-otlp-proto-grpc
          ps.opentelemetry-exporter-otlp-proto-http
          opentelemetry-instrumentation-asyncio ps.loguru ps.cryptography
          ps.argon2-cffi lark-oapi ps.google-genai ps.mcp ps.pathspec
        ];

        # tree-sitter language packages we don't carry in nixpkgs; strip from
        # the wheel's runtime metadata so the deps check passes.
        missingTreeSitter = [
          "tree-sitter-typescript"
          "tree-sitter-java"
          "tree-sitter-cpp"
          "tree-sitter-go"
          "tree-sitter-php"
          "tree-sitter-lua"
        ];

        # ---------- Variant 1: built from this source tree ----------
        # Drives setup.py inside a Nix sandbox: cargo for `ov_cli`, maturin for
        # `ragfs-python`, cmake for the C++ vectordb engine. Cargo deps are vendored
        # from Cargo.lock. web-studio is skipped (set OV_SKIP_STUDIO_BUILD=0 + add
        # nodejs to nativeBuildInputs to enable). First build may need iteration on
        # toolchain versions, sandbox networking, or per-crate quirks.

        openviking = ps.buildPythonPackage {
          pname = "openviking";
          version = "0.4.4-local";
          pyproject = true;

          src = ./.;

          cargoDeps = pkgs.rustPlatform.importCargoLock {
            lockFile = ./Cargo.lock;
            # Add `outputHashes` entries here if any crate has a git source.
          };

          nativeBuildInputs = [
            pkgs.rustPlatform.cargoSetupHook
            pkgs.cargo
            pkgs.rustc
            pkgs.cmake
            pkgs.maturin
            pkgs.pkg-config
            pkgs.gcc
            ps.setuptools
            ps.setuptools-scm
            ps.wheel
            ps.pythonRelaxDepsHook
          ];

          # pyproject.toml lists cmake/maturin in [build-system].requires as PyPI
          # packages, but here they come from nixpkgs as binaries on PATH. Skip
          # the python-side import check; the runtime invocations still work.
          pypaBuildFlags = [ "--skip-dependency-check" ];

          # setup.py probes maturin via importlib + invokes `python -m maturin`,
          # which assumes maturin is a Python distribution. nixpkgs ships maturin
          # only as a binary, so rewrite both probes to use the binary on PATH.
          postPatch = ''
            substituteInPlace setup.py --replace-fail \
              'if importlib.util.find_spec("maturin") is None:' \
              'if shutil.which("maturin") is None:'
            # Inside `build_args = [ ... ]` blocks, drop the `sys.executable,`
            # and `"-m",` lines so the maturin invocation runs the binary
            # directly. The cargo build_args is a single-line list, so its
            # range starts and ends on one line and is unaffected.
            sed -i '/build_args = \[/,/\]/ {
              /^[[:space:]]*sys\.executable,$/d
              /^[[:space:]]*"-m",$/d
            }' setup.py
          '';

          buildInputs = [
            pkgs.stdenv.cc.cc.lib
            pkgs.openssl
          ];

          propagatedBuildInputs = runtimeDeps;

          pythonRelaxDeps = true;
          pythonRemoveDeps = missingTreeSitter;
          dontUseCmakeConfigure = true; # setup.py drives cmake itself

          env = {
            SETUPTOOLS_SCM_PRETEND_VERSION = "0.4.4";
            OV_SKIP_STUDIO_BUILD = "1";
            OV_REQUIRE_RAGFS_BUILD = "1";
            # The C++ engine's CMakeLists.txt sets clang-only flags and the
            # vendored spdlog/leveldb pass -Werror, so any unsuppressed warning
            # under gcc becomes fatal. -w silences warnings entirely; the
            # nix cc-wrapper prepends this to every compile and FetchContent
            # subprojects inherit it via the same wrapper.
            NIX_CFLAGS_COMPILE = "-w";
          };

          doCheck = false;
          pythonImportsCheck = [ "openviking" "openviking_cli" ];
        };

        # ---------- Variant 2: PyPI wheel + local Python overlay ----------
        # Uses an upstream pre-built wheel for the native artifacts
        # (Rust ragfs_python*.so, the `ov` binary, vectordb *.abi3.so, web_studio
        # dist), then overlays this repo's openviking/ and openviking_cli/ Python
        # sources on top so edits to .py files take effect at runtime without
        # rebuilding anything native. The wheel native ABI may lag local Python;
        # bump `wheelVersion` and the URLs/hashes below if you hit a skew.

        wheelVersion = "0.3.9";
        wheelSrcs = {
          "x86_64-linux" = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/91/32/47fd915d8d4bb505e70617fc40ecf8c38cb9803b0229cef762a27d8a4ba7/openviking-0.3.9-cp310-abi3-manylinux_2_31_x86_64.whl";
            hash = "sha256-WzNG/Czrcku7kVRabVhlYb/FNlb7ou9C4qJ5A2d5fW4=";
          };
          "aarch64-linux" = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/71/6c/7ab0c2d7a1f89fa21ba957d49d4ebe752c93ff8aad5787266222f8787a59/openviking-0.3.9-cp310-abi3-manylinux_2_31_aarch64.whl";
            hash = "sha256-lh5MW2yRFC2ljyYJ2k026Sjy0irRws9ruzj3Ve2HcIw=";
          };
          "x86_64-darwin" = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/98/43/fc6fc57f94a74a7e6589effd77a32c465815fa45c053ef38eec2a5e9a2f4/openviking-0.3.9-cp310-abi3-macosx_15_0_x86_64.whl";
            hash = "sha256-Rta3hadl5t25zMGc/p2OOBB+Vu8Qj/UQyobFsPTfAmY=";
          };
          "aarch64-darwin" = pkgs.fetchurl {
            url = "https://files.pythonhosted.org/packages/15/ce/544cda93ad33e2cf2a01ef0229c1958486f63c304c833e44746320af7d4b/openviking-0.3.9-cp310-abi3-macosx_14_0_arm64.whl";
            hash = "sha256-HMwmgsK/5BciL1hkFkTRTxlyPmf0uhL9ccsP4mL9te8=";
          };
        };

        openviking-wheel = ps.buildPythonPackage {
          pname = "openviking-wheel";
          version = wheelVersion;
          format = "wheel";

          src = wheelSrcs.${system} or (throw "Unsupported system: ${system}");

          nativeBuildInputs = [ pkgs.autoPatchelfHook ps.pythonRelaxDepsHook ];

          pythonRemoveDeps = missingTreeSitter;

          buildInputs = [ pkgs.stdenv.cc.cc.lib ];
          propagatedBuildInputs = runtimeDeps;

          pythonRelaxDeps = true;
          doCheck = false;

          # Merge local source over the wheel-installed tree. Local files
          # overwrite their wheel counterparts; wheel-only files (lib/*.so,
          # bin/ov, web_studio/dist, vectordb engine *.abi3.so) remain because
          # the source tree has no counterpart for them.
          postInstall = ''
            site=$out/${python.sitePackages}
            chmod -R u+w "$site/openviking" "$site/openviking_cli"
            cp -rT --no-preserve=mode,ownership ${./openviking}     "$site/openviking"
            cp -rT --no-preserve=mode,ownership ${./openviking_cli} "$site/openviking_cli"
            chmod -R u+w "$site/openviking" "$site/openviking_cli"
            find "$site/openviking" "$site/openviking_cli" -name __pycache__ -exec rm -rf {} +
          '';
        };
      in {
        packages.default = openviking;
        packages.openviking = openviking;
        packages.openviking-wheel = openviking-wheel;

        devShells.default = pkgs.mkShell {
          packages = [
            (python.withPackages (_: runtimeDeps ++ [
              ps.setuptools ps.setuptools-scm ps.wheel ps.maturin ps.pip
              ps.pytest ps.pytest-asyncio
            ]))
            pkgs.cargo
            pkgs.rustc
            pkgs.cmake
            pkgs.pkg-config
            pkgs.gcc
            pkgs.openssl
          ];
          shellHook = ''
            export OV_SKIP_STUDIO_BUILD=1
            export SETUPTOOLS_SCM_PRETEND_VERSION=0.4.4
          '';
        };
      });
}
