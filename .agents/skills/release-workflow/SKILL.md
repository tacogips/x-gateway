---
name: release-workflow
description: Orchestrate x-gateway release operations end-to-end across GitHub release, binary artifacts, Nix validation, and npm publish. Use when users ask to release or publish a version.
allowed-tools: Bash, Read, Write, Grep, Glob
user-invocable: true
---

# Release Workflow Skill

This skill defines the release contract for x-gateway and routes execution to scope-specific release skills.

## When to Apply

Apply when the user asks to:
- release a version
- publish artifacts
- publish to npm
- create/update GitHub releases
- run release checks before tagging

## Scope Routing

Interpret release requests as follows:

1. Unscoped `release`:
- `github-release`
- `binary-release`
- `nix-release`
- `npm-release`

2. Scoped requests:
- GitHub only -> `github-release`
- Binary only -> `binary-release`
- Nix only -> `nix-release`
- npm only -> `npm-release`

If scope is ambiguous, default to full release contract.

## Release Contract For x-gateway

1. Validate working tree and branch state.
2. Validate release version from `package.json`.
3. Run quality gates (`task ci`).
4. Build release artifacts (library/CLI dist + optional compiled binaries).
5. Validate Nix reproducibility (`nix flake check`).
6. Publish GitHub release assets.
7. Publish npm package.
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
npm whoami
```
3. Toolchain:
```bash
bun --version
task --version
nix --version
```
4. Dependencies:
```bash
bun install --frozen-lockfile
```

## Standard Execution Order

1. `nix-release` (validation)
2. `binary-release` (artifacts)
3. `github-release` (tag + release page + asset upload)
4. `npm-release` (registry publish)

## Failure Handling

1. If `task ci` fails, stop release and surface failing command and file path.
2. If git tag already exists, verify tag target commit before creating release.
3. If GitHub release already exists, use upload/verify mode instead of recreate.
4. If npm version already exists, stop and request version bump (no forced overwrite).
5. If Nix check fails, stop and report flake-level remediation steps.

## Output Contract

Always return:
- Released version and tag (`vX.Y.Z`)
- GitHub release URL
- Uploaded asset names
- npm package/version confirmation
- Nix validation result (`nix flake check`)
- Any unresolved TODOs
