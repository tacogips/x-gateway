---
name: binary-release
description: Build multi-platform compiled binaries and distributable archives for x-gateway CLI executables.
allowed-tools: Bash, Read, Write, Grep, Glob
user-invocable: true
argument-hint: [target matrix or default all]
---

# Binary Release Skill

Use this skill to build compiled binaries for x-gateway and x-gateway-reader.

## Target Matrix (Default)

- `bun-darwin-arm64` -> `darwin-arm64`
- `bun-darwin-x64` -> `darwin-x64`
- `bun-linux-x64` -> `linux-x64`
- `bun-linux-arm64` -> `linux-arm64`

## Build Prerequisites

1. Install dependencies:
```bash
bun install --frozen-lockfile
```
2. Quality gates before packaging:
```bash
task ci
```
3. Resolve version:
```bash
VERSION=$(bun -e "const p = await Bun.file('./package.json').json(); console.log(p.version)")
```

## Build Commands

For each target/suffix pair, build both CLIs and archive them:

```bash
mkdir -p "release/x-gateway-v${VERSION}-${SUFFIX}/dist"
bun build src/main.ts --compile --target "$TARGET" --outfile "release/x-gateway-v${VERSION}-${SUFFIX}/x-gateway"
bun build src/main-reader.ts --compile --target "$TARGET" --outfile "release/x-gateway-v${VERSION}-${SUFFIX}/x-gateway-reader"
cp -r dist "release/x-gateway-v${VERSION}-${SUFFIX}/dist"
(
  cd release &&
  tar -czf "x-gateway-v${VERSION}-${SUFFIX}.tar.gz" "x-gateway-v${VERSION}-${SUFFIX}"
)
```

Also build npm tarball artifact:
```bash
rm -rf release/npm && mkdir -p release/npm
bun run build
bun pm pack --destination release
```

## Integrity File

Generate checksums:
```bash
(
  cd release &&
  sha256sum *.tar.gz *.tgz > SHA256SUMS.txt
)
```

## Verification

1. Ensure all archives exist under `release/`.
2. Run local smoke test on host-compatible artifact:
```bash
./release/x-gateway-v${VERSION}-<host-suffix>/x-gateway version
./release/x-gateway-v${VERSION}-<host-suffix>/x-gateway-reader version
```
3. Ensure checksums file exists and is non-empty.

## Failure Handling

1. If `--compile` target fails, report unsupported target and continue with remaining targets only if user allows partial release.
2. If binary runs but `version` fails, stop and mark artifact invalid.
3. If `bun pm pack` fails, stop before GitHub/npm publish.
