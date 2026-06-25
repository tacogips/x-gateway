# Homebrew Packaging

This project ships two Homebrew release paths:

- Formula: unsigned tarballs containing `bin/x-gateway-read` and
  `bin/x-gateway-write`.
- Cask: signed, notarized, and stapled macOS DMGs containing the command line tool.

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
scripts/render-homebrew-formula.sh <version> ../homebrew-tap/Formula/x-gateway.rb
scripts/render-homebrew-formula.sh <version> ../homebrew-tap/Formula/x-gateway-read.rb read
scripts/render-homebrew-formula.sh <version> ../homebrew-tap/Formula/x-gateway-write.rb write
```

The combined `x-gateway` formula installs both commands. The command-specific
`x-gateway-read` and `x-gateway-write` formulae reuse the same release archive
but install only their matching executable.

Do not install the combined formula together with the command-specific formulae;
they intentionally link the same executable names.

## Cask

Build signed and notarized DMGs on macOS:

```bash
kinko exec --env APPLE_SIGNING_IDENTITY,APPLE_ID,APPLE_PASSWORD,APPLE_TEAM_ID -- \
  scripts/build-homebrew-cask-release.sh darwin-arm64 darwin-x64
```

This writes:

```text
dist/homebrew-cask/x-gateway-<version>-darwin-arm64.dmg
dist/homebrew-cask/x-gateway-<version>-darwin-arm64.dmg.sha256
dist/homebrew-cask/x-gateway-<version>-darwin-x64.dmg
dist/homebrew-cask/x-gateway-<version>-darwin-x64.dmg.sha256
```

Render the Cask:

```bash
scripts/render-homebrew-cask.sh <version> ../homebrew-tap/Casks/x-gateway.rb
```

For a tagged release, the local wrapper verifies the tag, builds DMGs, uploads
release assets, and renders the tap Cask:

```bash
kinko exec --env APPLE_SIGNING_IDENTITY,APPLE_ID,APPLE_PASSWORD,APPLE_TEAM_ID -- \
  scripts/release-homebrew-cask-local.sh v<version>
```

## Verification

From the tap checkout:

```bash
ruby -c Formula/x-gateway.rb
ruby -c Formula/x-gateway-read.rb
ruby -c Formula/x-gateway-write.rb
brew audit --strict x-gateway || brew audit --strict --formula x-gateway
brew audit --strict x-gateway-read || brew audit --strict --formula x-gateway-read
brew audit --strict x-gateway-write || brew audit --strict --formula x-gateway-write
brew fetch --formula tacogips/homebrew-tap/x-gateway
brew fetch --formula tacogips/homebrew-tap/x-gateway-read
brew fetch --formula tacogips/homebrew-tap/x-gateway-write
brew fetch --cask tacogips/homebrew-tap/x-gateway
HOMEBREW_NO_GITHUB_API=1 brew audit --cask tacogips/homebrew-tap/x-gateway
```

If online audit fails due local GitHub credentials or rate limits, run the
non-online audit and record the limitation.
