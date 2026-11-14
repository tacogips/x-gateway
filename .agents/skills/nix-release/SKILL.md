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

`x-gateway` currently defines a development shell in `flake.nix` and does not publish a dedicated Nix package output.

For this repository, Nix release scope means:
1. Validate flake health (`nix flake check`)
2. Validate dev shell reproducibility (`nix develop -c ...`)
3. Optionally update and commit `flake.lock` when requested

## Standard Validation Commands

```bash
nix flake show
nix flake check
nix develop -c bun --version
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
2. `nix develop` successfully exposes bun/task toolchain.
3. `flake.lock` diff is intentional and reviewed.
4. No uncommitted lockfile drift remains at release tag time.

## Failure Handling

1. If `nix flake check` fails, stop release and report exact failing derivation or check.
2. If upstream input is unavailable/transient, retry once then report deterministic failure.
3. If lock update introduces breakage, revert lock update and proceed with validate-only mode.
