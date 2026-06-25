---
name: homebrew-release
description: Use when building, validating, publishing, or tap-rendering Homebrew formula tarball releases for this Swift project, including scripts/build-homebrew-release.sh, scripts/render-homebrew-formula.sh, and task build:homebrew, homebrew:formula-reader, or homebrew:formula-writer commands.
---

# Homebrew Release

Use this skill for Formula releases installed with:

```bash
brew tap tacogips/homebrew-tap
brew install x-gateway-reader
brew install x-gateway-writer
```

The release archive contains both command products:

- `x-gateway-reader`
- `x-gateway-writer`

Render two formulae from the same archive:

- `x-gateway-reader`: installs only `x-gateway-reader`
- `x-gateway-writer`: installs only `x-gateway-writer`

## Release Contract

1. Confirm `VERSION` is the intended release version.
2. Build and test the Swift package.
3. Build macOS Homebrew tarballs with `scripts/build-homebrew-release.sh`.
4. Publish the tarballs to a GitHub Release only when explicitly requested.
5. Render the formula only after all referenced archives and checksums exist.
6. Update and verify the tap formula from the tap checkout.

The default Swift formula contract is macOS-only:

| Homebrew platform | Release asset |
| --- | --- |
| macOS Apple Silicon | `x-gateway-<version>-darwin-arm64.tar.gz` |
| macOS Intel | `x-gateway-<version>-darwin-x64.tar.gz` |

Do not add Linux assets unless the project has a reviewed Swift Linux runtime
contract.

## Standard Commands

Build:

```bash
task build
task test
task build:homebrew -- darwin-arm64 darwin-x64
```

Render locally:

```bash
version="$(tr -d '[:space:]' < VERSION)"
task homebrew:formula-reader -- "$version"
task homebrew:formula-writer -- "$version"
```

Render into the default sibling tap:

```bash
version="$(tr -d '[:space:]' < VERSION)"
task homebrew:tap-formula-reader -- "$version"
task homebrew:tap-formula-writer -- "$version"
```

For a custom tap path:

```bash
version="$(tr -d '[:space:]' < VERSION)"
scripts/render-homebrew-formula.sh "$version" reader /path/to/homebrew-tap/Formula/x-gateway-reader.rb
scripts/render-homebrew-formula.sh "$version" writer /path/to/homebrew-tap/Formula/x-gateway-writer.rb
```

## Publishing Notes

Before rendering a formula for public use, ensure the GitHub Release assets
exist:

```bash
version="$(tr -d '[:space:]' < VERSION)"
gh release view "v${version}" --repo tacogips/x-gateway
```

If publishing is explicitly requested:

```bash
version="$(tr -d '[:space:]' < VERSION)"
gh release upload "v${version}" \
  "dist/homebrew/x-gateway-${version}-darwin-arm64.tar.gz" \
  "dist/homebrew/x-gateway-${version}-darwin-arm64.tar.gz.sha256" \
  "dist/homebrew/x-gateway-${version}-darwin-x64.tar.gz" \
  "dist/homebrew/x-gateway-${version}-darwin-x64.tar.gz.sha256" \
  --repo tacogips/x-gateway \
  --clobber
```

## Verification

From the tap checkout:

```bash
ruby -c Formula/x-gateway-reader.rb
ruby -c Formula/x-gateway-writer.rb
brew audit --strict x-gateway-reader || brew audit --strict --formula x-gateway-reader
brew audit --strict x-gateway-writer || brew audit --strict --formula x-gateway-writer
brew fetch --formula tacogips/homebrew-tap/x-gateway-reader
brew fetch --formula tacogips/homebrew-tap/x-gateway-writer
brew install tacogips/homebrew-tap/x-gateway-reader
x-gateway-reader version
brew test tacogips/homebrew-tap/x-gateway-reader
brew install tacogips/homebrew-tap/x-gateway-writer
x-gateway-writer version
brew test tacogips/homebrew-tap/x-gateway-writer
```

If online audit fails because of local GitHub credentials or rate limits, run a
non-online audit and report the limitation.
