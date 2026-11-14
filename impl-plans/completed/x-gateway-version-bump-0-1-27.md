# Version Bump to 0.1.27

**Status**: Completed
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

- [x] `VERSION` contains exactly `0.1.27` followed by a single trailing newline. Keep the existing newline style (fresh-read the file first).
- [x] `Sources/XGatewayCore/XGatewayCore.swift`: `"version": "0.1.26"` becomes `"version": "0.1.27"` in the `if group == "version"` block. That is the only change.

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
- [x] `cat VERSION` prints `0.1.27`.
- [x] `grep -n '"version": "0.1.27"' Sources/XGatewayCore/XGatewayCore.swift` shows exactly one hit.
- [x] `grep -rn '0\.1\.26' VERSION Sources` produces no output.
- [x] `git diff --stat -- VERSION Sources/XGatewayCore/XGatewayCore.swift` shows 2 files changed, 2 insertions(+), 2 deletions(-).

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

- 2026-10-27: Step 6 implemented the two version literals only. Pre-edit SHA-256: `VERSION` `2f9d5846cd782c38fbe467cf86ec1401dd1b648c42ea4376b1e82c7fb62f4edf`; `XGatewayCore.swift` `0a0277b51965180ba6f58b892c444b60bec9009f31a8a6e9a733bb61e0b1a11a`. Post-edit SHA-256: `VERSION` `246a6387221ae9ed8e7b362df6959a816c0a2a1e8f98481beec0cecfe3976486`; `XGatewayCore.swift` `d5eca0b995059de211aaad658bd47a44868661f2d3d236dbe5147eae7b47ffab`. Scoped checks passed: `cat VERSION` (exit 0), version literal grep (exit 0, one hit), old version grep (exit 1, empty output as expected), and diff stat (exit 0, 2 files / 2 insertions / 2 deletions). Selected-file `swiftlint lint --strict --quiet --no-cache` passed (exit 0). No Swift build/test ran per wave 1 contract. Formal review and commit/push/tag remain downstream.
- 2026-10-27: The combined-tree integration ran `swift build`, `swift test` (68 tests, 0 failures), `mise run test` and `mise run lint`, all exit 0. `swift run x-gateway-reader version` reported `0.1.27` (`tmp/x-gateway-swift-crypto-5-upgrade-20261027/swift-crypto-5-dependency/021-integration-version-runtime.log`). Step 7 review accepted the plan with no findings. Step 8 marked it Completed and requested an archive to `impl-plans/completed/x-gateway-version-bump-0-1-27.md`. The commit, the push to `origin/main`, then tag `v0.1.27` on the pushed HEAD, remain serial finalization steps.
