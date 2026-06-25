# Homebrew Packaging

This project ships command-specific Homebrew Formula releases:

- Formula: unsigned tarballs containing `bin/x-gateway-read` and
  `bin/x-gateway-write`.

Swift formula archives are macOS-only by default. Add Linux archives only after
the project has a reviewed Swift Linux build and runtime contract.

## Formula

Build release archives:

```bash
scripts/build-homebrew-release.sh darwin-arm64 darwin-x64
```

The command writes archives and checksums under `dist/homebrew/`:

```text
dist/homebrew/x-gateway-<version>-darwin-arm64.tar.gz
dist/homebrew/x-gateway-<version>-darwin-arm64.tar.gz.sha256
dist/homebrew/x-gateway-<version>-darwin-x64.tar.gz
dist/homebrew/x-gateway-<version>-darwin-x64.tar.gz.sha256
```

Publish those assets to the GitHub release named `v<version>`, then render the
formulae into a tap checkout:

```bash
scripts/render-homebrew-formula.sh <version> read ../homebrew-tap/Formula/x-gateway-read.rb
scripts/render-homebrew-formula.sh <version> write ../homebrew-tap/Formula/x-gateway-write.rb
```

The command-specific `x-gateway-read` and `x-gateway-write` formulae reuse the
same release archive but install only their matching executable.

## Verification

From the tap checkout:

```bash
ruby -c Formula/x-gateway-read.rb
ruby -c Formula/x-gateway-write.rb
brew audit --strict x-gateway-read || brew audit --strict --formula x-gateway-read
brew audit --strict x-gateway-write || brew audit --strict --formula x-gateway-write
brew fetch --formula tacogips/homebrew-tap/x-gateway-read
brew fetch --formula tacogips/homebrew-tap/x-gateway-write
```

If online audit fails due local GitHub credentials or rate limits, run the
non-online audit and record the limitation.
