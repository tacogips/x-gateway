---
name: nix-release
description: Execute Nix release validation for x-gateway by verifying flake reproducibility, lockfile integrity, and optional lock updates.
allowed-tools: Bash, Read, Write, Grep, Glob
user-invocable: true
argument-hint: [validate-only|update-lock]
---

# Nix Release Skill

Use this skill for release-time Nix validation and optional lock refresh.

## Release Intent In This Repository

`x-gateway` defines a development shell and release-backed Darwin package
outputs in `flake.nix`.

Package outputs:

- `.#x-gateway`: installs both commands
- `.#x-gateway-read`: installs only `x-gateway-read`
- `.#x-gateway-write`: installs only `x-gateway-write`

App outputs:

- `.#x-gateway-read`
- `.#x-gateway-write`

For this repository, Nix release scope means:
1. Validate flake health (`nix flake check`)
2. Validate command-specific package builds (`nix build .#x-gateway-read`,
   `nix build .#x-gateway-write`)
3. Validate command-specific apps (`nix run .#x-gateway-read -- version`,
   `nix run .#x-gateway-write -- version`)
4. Validate dev shell reproducibility (`nix develop -c ...`)
5. Optionally update and commit `flake.lock` when requested

## Standard Validation Commands

```bash
nix flake show
nix flake check
nix build .#x-gateway-read
nix build .#x-gateway-write
nix run .#x-gateway-read -- version
nix run .#x-gateway-write -- version
nix develop -c task --version
```

## Optional Lock Update Flow

Only when user requests dependency refresh:

```bash
nix flake update
git diff -- flake.lock
```

If updates are accepted, include `flake.lock` in the release commit before tagging.

## Verification Checklist

1. `nix flake check` passes.
2. `nix build .#x-gateway-read` and `nix build .#x-gateway-write` pass on a
   supported Darwin system.
3. `nix run .#x-gateway-read -- version` and
   `nix run .#x-gateway-write -- version` report the release version.
4. `nix develop` successfully exposes the expected toolchain.
5. `flake.lock` diff is intentional and reviewed.
6. No uncommitted lockfile drift remains at release tag time.

## Failure Handling

1. If `nix flake check` fails, stop release and report exact failing derivation or check.
2. If upstream input is unavailable/transient, retry once then report deterministic failure.
3. If lock update introduces breakage, revert lock update and proceed with validate-only mode.
