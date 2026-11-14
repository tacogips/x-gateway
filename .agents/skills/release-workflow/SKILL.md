---
name: release-workflow
description: Orchestrate x-gateway release operations end-to-end across Swift binary artifacts, GitHub release assets, Homebrew formulae, and Nix validation. Use when users ask to release or publish a version.
allowed-tools: Bash, Read, Write, Grep, Glob
user-invocable: true
---

# Release Workflow Skill

This skill defines the release contract for x-gateway and routes execution to scope-specific release skills.

## When to Apply

Apply when the user asks to:
- release a version
- publish artifacts
- create/update GitHub releases
- create/update Homebrew tap formulae
- validate Nix package outputs
- run release checks before tagging

## Scope Routing

Interpret release requests as follows:

1. Unscoped `release`:
- `binary-release`
- `github-release`
- `homebrew-release`
- `nix-release`

2. Scoped requests:
- GitHub only -> `github-release`
- Binary only -> `binary-release`
- Homebrew only -> `homebrew-release`
- Nix only -> `nix-release`

If scope is ambiguous, default to full release contract.

## Release Contract For x-gateway

1. Validate working tree and branch state.
2. Validate release version from `VERSION`.
3. Run quality gates (`task ci`).
4. Build macOS Swift binary archives with `task build:homebrew -- darwin-arm64 darwin-x64`.
5. Publish GitHub release assets for the tag.
6. Render and publish Homebrew formulae for `x-gateway-reader` and `x-gateway-writer`.
7. Validate Nix reproducibility (`nix flake check`) and command-specific package/app outputs.
8. Verify release visibility and report exact URLs/versions.

## Preconditions

1. Clean and up-to-date branch:
```bash
git status --short
git fetch --tags origin
```
2. Auth:
```bash
gh auth status
```
3. Toolchain:
```bash
swift --version
task --version
nix --version
```

## Standard Execution Order

1. `binary-release` (Swift macOS archives)
2. `github-release` (tag + release page + asset upload)
3. `homebrew-release` (tap formula render, commit, and verification)
4. `nix-release` (local and remote validation)

## Failure Handling

1. If `task ci` fails, stop release and surface failing command and file path.
2. If git tag already exists, verify tag target commit before creating release.
3. If GitHub release already exists, use upload/verify mode instead of recreate.
4. If Homebrew formula rendering references missing archives or checksums, rebuild artifacts before committing the tap.
5. If Nix check fails, stop and report flake-level remediation steps.

## Output Contract

Always return:
- Released version and tag (`vX.Y.Z`)
- GitHub release URL
- Uploaded asset names
- Homebrew formula names and tap commit
- Nix validation result (`nix flake check`)
- Any unresolved TODOs
