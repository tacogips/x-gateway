# Homebrew Packaging

This project ships command-specific Homebrew Formula releases:

- Formula: unsigned tarballs containing `bin/x-gateway-reader` and
  `bin/x-gateway-writer`.

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
scripts/render-homebrew-formula.sh <version> reader ../homebrew-tap/Formula/x-gateway-reader.rb
scripts/render-homebrew-formula.sh <version> writer ../homebrew-tap/Formula/x-gateway-writer.rb
```

The command-specific `x-gateway-reader` and `x-gateway-writer` formulae reuse the
same release archive but install only their matching executable.

## Verification

From the tap checkout:

```bash
ruby -c Formula/x-gateway-reader.rb
ruby -c Formula/x-gateway-writer.rb
brew audit --strict x-gateway-reader || brew audit --strict --formula x-gateway-reader
brew audit --strict x-gateway-writer || brew audit --strict --formula x-gateway-writer
brew fetch --formula tacogips/homebrew-tap/x-gateway-reader
brew fetch --formula tacogips/homebrew-tap/x-gateway-writer
```

If online audit fails due local GitHub credentials or rate limits, run the
non-online audit and record the limitation.
