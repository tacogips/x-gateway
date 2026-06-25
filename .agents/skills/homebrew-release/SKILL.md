---
name: homebrew-release
description: Use when building, validating, publishing, or tap-rendering Homebrew formula tarball releases for this Swift project, including scripts/build-homebrew-release.sh, scripts/render-homebrew-formula.sh, and task build:homebrew or homebrew:formula commands.
---

# Homebrew Release

Use this skill for Formula releases installed with:

```bash
brew tap tacogips/homebrew-tap
brew install x-gateway
brew install x-gateway-read
brew install x-gateway-write
```

Use `.agents/skills/macos-cask-release/SKILL.md` for signed and notarized Cask
DMGs.

The release archive contains both command products:

- `x-gateway-read`
- `x-gateway-write`

Render three formulae from the same archive:

- `x-gateway`: installs both commands
- `x-gateway-read`: installs only `x-gateway-read`
- `x-gateway-write`: installs only `x-gateway-write`

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
task homebrew:formula -- "$version"
task homebrew:formula-read -- "$version"
task homebrew:formula-write -- "$version"
```

Render into the default sibling tap:

```bash
version="$(tr -d '[:space:]' < VERSION)"
task homebrew:tap-formula -- "$version"
task homebrew:tap-formula-read -- "$version"
task homebrew:tap-formula-write -- "$version"
```

For a custom tap path:

```bash
version="$(tr -d '[:space:]' < VERSION)"
scripts/render-homebrew-formula.sh "$version" /path/to/homebrew-tap/Formula/x-gateway.rb
scripts/render-homebrew-formula.sh "$version" /path/to/homebrew-tap/Formula/x-gateway-read.rb read
scripts/render-homebrew-formula.sh "$version" /path/to/homebrew-tap/Formula/x-gateway-write.rb write
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
  "dist/homebrew/x-gateway-${version}-darwin-x64.tar.gz" \
  --repo tacogips/x-gateway \
  --clobber
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
brew install tacogips/homebrew-tap/x-gateway
x-gateway-read version
x-gateway-write version
brew test tacogips/homebrew-tap/x-gateway
brew install tacogips/homebrew-tap/x-gateway-read
x-gateway-read version
brew test tacogips/homebrew-tap/x-gateway-read
brew install tacogips/homebrew-tap/x-gateway-write
x-gateway-write version
brew test tacogips/homebrew-tap/x-gateway-write
```

If online audit fails because of local GitHub credentials or rate limits, run a
non-online audit and report the limitation.
