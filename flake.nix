{
  description = "x-gateway Swift development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    git-hooks.url = "github:cachix/git-hooks.nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      git-hooks,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = pkgs.lib;

        runtimePackages =
          with pkgs;
          [
            gh
            git
            go-task
            swiftlint
          ]
          ++ lib.optionals pkgs.stdenv.isLinux [
            swift
          ];

        devOnlyPackages = with pkgs; [
          gitleaks
        ];

        preCommitCheck = git-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            gitleaks = {
              enable = true;
              name = "gitleaks";
              entry = "${pkgs.lib.getExe pkgs.gitleaks} git --pre-commit --redact --staged --verbose";
              language = "system";
              pass_filenames = false;
            };
          };
        };

        devPackages = runtimePackages ++ devOnlyPackages ++ preCommitCheck.enabledPackages;
        version = builtins.replaceStrings [ "\n" "\r" " " ] [ "" "" "" ] (builtins.readFile ./VERSION);
        releaseArtifacts = {
          aarch64-darwin = {
            target = "darwin-arm64";
            hash = "sha256-niLEPE6GQWHof7Cjtms9cOqko0q9XCvYOOPXgUSgQwY=";
          };
          x86_64-darwin = {
            target = "darwin-x64";
            hash = "sha256-xesyhDFdAg8GpMeUPztMnDM9hUJ6qMWkQjttiEAsa90=";
          };
        };
        hasReleaseArtifact = builtins.hasAttr system releaseArtifacts;
        releaseArtifact = builtins.getAttr system releaseArtifacts;
        releaseBaseUrl = "https://github.com/tacogips/x-gateway/releases/download/v${version}";
        mkCommandPackage =
          command:
          pkgs.stdenvNoCC.mkDerivation {
            pname = command;
            inherit version;

            src = pkgs.fetchurl {
              url = "${releaseBaseUrl}/x-gateway-${version}-${releaseArtifact.target}.tar.gz";
              hash = releaseArtifact.hash;
            };

            unpackPhase = ''
              tar -xzf "$src"
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p "$out/bin"
              install -m 0755 "bin/${command}" "$out/bin/${command}"
              runHook postInstall
            '';

            meta = {
              description =
                if command == "x-gateway-read" then
                  "Read-only X API gateway CLI"
                else
                  "Write-capable X API gateway CLI";
              homepage = "https://github.com/tacogips/x-gateway";
              license = lib.licenses.mit;
              mainProgram = command;
              platforms = builtins.attrNames releaseArtifacts;
            };
          };
        commandPackages =
          if hasReleaseArtifact then
            rec {
              x-gateway-read = mkCommandPackage "x-gateway-read";
              x-gateway-write = mkCommandPackage "x-gateway-write";
              x-gateway = pkgs.buildEnv {
                name = "x-gateway-${version}";
                paths = [
                  x-gateway-read
                  x-gateway-write
                ];
                pathsToLink = [ "/bin" ];
              };
              default = x-gateway;
            }
          else
            { };
        commandApps =
          if hasReleaseArtifact then
            {
              x-gateway-read = {
                type = "app";
                program = "${commandPackages.x-gateway-read}/bin/x-gateway-read";
                meta.description = "Run the read-only X API gateway CLI";
              };
              x-gateway-write = {
                type = "app";
                program = "${commandPackages.x-gateway-write}/bin/x-gateway-write";
                meta.description = "Run the write-capable X API gateway CLI";
              };
            }
          else
            { };
      in
      {
        packages = commandPackages // {
          dev-tools = pkgs.buildEnv {
            name = "x-gateway-dev-tools";
            paths = devPackages;
            pathsToLink = [ "/bin" ];
          };
        };

        apps = commandApps;

        checks.pre-commit-check = preCommitCheck;

        devShells.default = pkgs.mkShell {
          packages = devPackages;

          shellHook = ''
            ${preCommitCheck.shellHook}

            echo "x-gateway Swift development environment ready"
            echo "Swift version: $(swift --version 2>/dev/null | head -n 1 || echo 'not available')"
            echo "Task version: $(task --version 2>/dev/null || echo 'not available')"
            echo "SwiftLint version: $(swiftlint version 2>/dev/null || echo 'not available')"
            echo "Gitleaks version: $(gitleaks version 2>/dev/null || echo 'not available')"
          '';
        };
      }
    );
}
