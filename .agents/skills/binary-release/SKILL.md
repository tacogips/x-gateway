---
name: binary-release
description: Build macOS Swift binary archives for the x-gateway reader and writer CLI executables.
allowed-tools: Bash, Read, Write, Grep, Glob
user-invocable: true
argument-hint: [target matrix or default all]
---

# Binary Release Skill

Use this skill to build compiled Swift binaries for `x-gateway-reader` and `x-gateway-writer`.

## Target Matrix (Default)

- `darwin-arm64`
- `darwin-x64`

## Build Prerequisites

1. Quality gates before packaging:
```bash
task ci
```
2. Resolve version:
```bash
VERSION=$(tr -d '[:space:]' < VERSION)
```

## Build Commands

Build macOS Homebrew archives containing both remaining binaries:

```bash
task build:homebrew -- darwin-arm64 darwin-x64
```

## Integrity File

Generate checksums:
```bash
(
  cd dist/homebrew &&
  shasum -a 256 x-gateway-"${VERSION}"-*.tar.gz
)
```

## Verification

1. Ensure both archives and `.sha256` files exist under `dist/homebrew/`.
2. Run local smoke test on host-compatible artifact:
```bash
tar -tzf "dist/homebrew/x-gateway-${VERSION}-darwin-arm64.tar.gz" | grep './bin/x-gateway-reader'
tar -tzf "dist/homebrew/x-gateway-${VERSION}-darwin-arm64.tar.gz" | grep './bin/x-gateway-writer'
```
3. Ensure checksum files exist and are non-empty.

## Failure Handling

1. If a Swift cross-build target fails, report the target and do not publish a partial release unless explicitly requested.
2. If binary runs but `version` fails, stop and mark artifact invalid.
3. If archive contents do not include both binaries, stop before GitHub publish.
