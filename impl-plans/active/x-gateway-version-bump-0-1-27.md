# Version Bump to 0.1.27

**Status**: Ready
**Plan ID**: `version-bump-0-1-27`
**Wave**: 1 (no dependencies; runs in parallel with `swift-crypto-5-dependency`)
**Design Reference**: `design-docs/specs/architecture.md#versioning-and-tagging`
**Issue**: workflowInput `x-gateway: move to swift-crypto 5.x` (no remote issue number)

## Purpose

A dependency-only change bumps the patch version. The repo convention keeps the
version in two places that must match: `VERSION` and the `"version"` value
returned for the `version` group in `Sources/XGatewayCore/XGatewayCore.swift`
(currently line 175). Both move from `0.1.26` to `0.1.27`. Riela pins the
`v0.1.27` tag, which finalization creates after this plan and the dependency plan
are committed and pushed together.

## Non-Goals

- No commit, push, or tag. Finalization serially runs `git push origin main`, then `git tag v0.1.27` on the pushed HEAD, then `git push origin v0.1.27`.
- No GitHub release and no Homebrew/Cask/npm/Nix changes. Do not touch `Formula/`, `packaging/`, `dist/`, `scripts/`, `flake.nix`, or `mise.toml`.
- Do not touch `Package.swift`, `Package.resolved`, or any crypto source file. Plan `swift-crypto-5-dependency` owns those.
- Do not change any other string in `XGatewayCore.swift`.

## Deliverables

- [ ] `VERSION` contains exactly `0.1.27` followed by a single trailing newline. Keep the existing newline style (fresh-read the file first).
- [ ] `Sources/XGatewayCore/XGatewayCore.swift`: `"version": "0.1.26"` becomes `"version": "0.1.27"` in the `if group == "version"` block. That is the only change.

## Invariants

- `grep -rn '0\.1\.26' VERSION Sources` returns nothing after the edit. If another occurrence exists in Sources, report it and do not change it silently. Only the two known sites are in scope.
- The `"name": "x-gateway"` and `"runtime": "swift"` keys are unchanged.

## Tasks

### TASK-001: Bump both version sites

**Parallelizable**: Yes (wave 1)

1. Fresh-read `VERSION` and `Sources/XGatewayCore/XGatewayCore.swift`, and record `shasum -a 256` for both.
2. Edit `VERSION` to `0.1.27`.
3. Edit the single `"version": "0.1.26"` literal to `"0.1.27"`. Use an exact-string edit. Do not use a global regex replace across the file.
4. Record the post-edit sha256 values in the Progress Log.

Pitfalls:
- Do not run `swift build` or `swift test` here. The parallel dependency plan owns `.build` during wave 1, and concurrent SwiftPM runs contend for the `.build` lock. Integration review covers full build and test.
- Do not add a `v` prefix inside `VERSION`.

**Completion Criteria**:
- [ ] `cat VERSION` prints `0.1.27`.
- [ ] `grep -n '"version": "0.1.27"' Sources/XGatewayCore/XGatewayCore.swift` shows exactly one hit.
- [ ] `grep -rn '0\.1\.26' VERSION Sources` produces no output.
- [ ] `git diff --stat -- VERSION Sources/XGatewayCore/XGatewayCore.swift` shows 2 files changed, 2 insertions(+), 2 deletions(-).

## Verification Commands (scoped to this plan)

| Command | Must establish |
|---|---|
| `cat VERSION` | `0.1.27` |
| `grep -n '"version": "0.1.27"' Sources/XGatewayCore/XGatewayCore.swift` | exactly 1 line |
| `grep -rn '0\.1\.26' VERSION Sources` | no output (exit 1) |
| `git diff --stat -- VERSION Sources/XGatewayCore/XGatewayCore.swift` | 2 files, 2+/2- |

At integration, `swift build`, `swift test`, `mise run test`, and `mise run lint` validate the constant in context.

## Concurrency and Drift Rules

- Fresh-read before each edit and record sha256 before and after.
- If a file changed between your read and your write without your involvement, stop and report drift.
- No git write operations.

## Progress Log

- 2026-10-27: Plan created from the accepted design (Step 3 accepted, no findings).
