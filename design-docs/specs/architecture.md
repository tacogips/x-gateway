# Architecture

## Status

Draft

## Overview

`x-gateway` is a Swift Package Manager project with the `XGatewayCore` library
target, separate `x-gateway-reader` and `x-gateway-writer` executable targets, a
Swift smoke-test executable, and release automation for Homebrew.

The stable runtime is organized around a project-owned GraphQL contract, a
capability planner, and reviewed transport adapters. Public callers express
intent through stable fields such as `followingTimeline(...)`; the planner maps
those fields to capability ids, and adapter modules own upstream request shape.
Cursor- or Codex-specific behavior must stay outside this core boundary unless
it is implemented through an explicit adapter module.

## Agent CLI Reference Adapter Boundary

Issue source: Step 1 intake for Codex-agent reference behavior and future
Cursor CLI behavior mapping in `codex-design-and-implement-review-loop`
issue-resolution mode.

The local Codex reference for agent process behavior is
`../codex-agent` in this checkout, as established by the Step 1 intake. The
intake-requested default
`../../codex-agent` path is not present from this repository root, so design
work uses the nearest local reference repository without copying its CLI argv
shape into `x-gateway` core.

Reference files used:

- `../codex-agent/src/process/types.ts`
- `../codex-agent/src/process/manager.ts`
- `../codex-agent/src/process/manager.test.ts`
- `../codex-agent/src/sdk/agent-runner.ts`
- `../codex-agent/src/sdk/agent-runner.test.ts`
- `../codex-agent/src/sdk/agent-runner.process-options.test.ts`

Codex-reference behavior from `codex-agent` is treated as an adapter reference,
not a direct public contract for this project:

- A stable request option, such as "reasoning effort", must be represented in
  project-owned request metadata before any provider-specific argv is built.
- Codex CLI config overrides remain a Codex adapter concern. The reference
  forwards `configOverrides` as repeated `-c <override>` arguments for both new
  and resumed sessions.
- The intended data flow is: stable request metadata -> capability validation ->
  provider adapter selection -> provider-specific argv construction ->
  subprocess launch.
- Cursor CLI behavior must live behind a separate Cursor adapter module if it
  is introduced. Cursor flags, environment variables, defaults, or resume
  semantics must not leak into the public GraphQL contract or shared capability
  planner.
- A Cursor adapter must publish capability metadata that states whether
  reasoning effort is supported for new sessions, resumed sessions, both, or
  neither.
- Intentional divergence from Codex behavior must be documented at the adapter
  boundary, including whether Cursor supports the same reasoning-effort values,
  whether the setting applies to resumed sessions, and how unsupported values
  fail validation.
- Adapter validation must reject unsupported reasoning-effort values and
  unsupported resume semantics before subprocess launch. A provider adapter must
  never silently drop a stable request option.

Rollout constraints for this issue:

- This design update is documentation-only and does not introduce an agent-runner
  capability to the stable `x-gateway` runtime.
- A future implementation must add a provider-adapter boundary before accepting
  Cursor-specific process options. It must not add Cursor argv construction to
  the public GraphQL parser, capability planner, or shared executor.
- Capability metadata must be the rollout gate for provider-specific behavior:
  unsupported values, unsupported resume behavior, and unavailable adapters fail
  validation before any subprocess is launched.
- Codex reference parity is limited to the stable behavior identified by Step 1:
  `configOverrides` are preserved for both new and resumed Codex sessions. Any
  Cursor mismatch is allowed only when documented as an intentional adapter
  divergence.

## Targets

- `XGatewayCore`: domain, GraphQL contract, projection, auth, and live transport
  adapters.
- `XGatewayRead`: read-only command entry point.
- `XGatewayWrite`: write command entry point.
- `XGatewaySwiftSmokeTests`: executable smoke-test harness used by `mise run test`.

## Capability Matrix Implementation Target

- Public GraphQL fields must map to reviewed capability ids before execution.
- Capability metadata, public-field registration, and executor dispatch must
  remain aligned; drift between those registries is an architecture bug.
- Transport adapters decide upstream field sets and pagination mechanics, but
  they must not leak raw X web GraphQL document ids, feature flags, or rollout
  toggles into the public contract.
- X MCP parity fields added from the current official X MCP and X API docs must
  keep project-owned names even when the upstream endpoint naming still uses
  legacy `tweet` or `retweet` route segments.
- Basic MCP parity currently covers user lookup, post likers, post reposters,
  quote-post lookup, recent post counts, bookmark listing, bookmark add, and
  bookmark removal.
- `followingTimeline(...)` maps to `timeline.following` and is a bounded
  aggregate over followed-account timelines, not a native upstream home-timeline
  cursor.
- Followed-account timeline fanout must request public tweet fields only from
  the metric field families. It keeps `public_metrics`, omits owner-only
  `organic_metrics` and `promoted_metrics`, and preserves nullable
  `metrics.impressionCount` when no reviewed public impression source is
  available.
- Owner-only metric groups may be used only by a reviewed self-owned read path
  where the authenticated user is permitted to access those metrics.
- Aggregate pagination tokens for `followingTimeline(...)` must be
  project-owned. Until a reviewed merged cursor exists, the stable behavior is a
  bounded first slice with no upstream cursor passthrough.

## Third-Party Dependency Baseline

Issue source: workflow input `x-gateway: move to swift-crypto 5.x` (no remote
issue number). Riela pins `x-gateway` by `exact:` version tag and must resolve
a single swift-crypto 5.x across its dependency graph.

- `Package.swift` is the only manifest. Its only direct dependency is
  `apple/swift-crypto`, required as `from: "5.0.3"` (previously
  `"3.0.0"..<"5.0.0"`). Ranges that admit 3.x or 4.x, or an upper bound below
  6.0.0, are not allowed. `swift-asn1` is transitive and may move to whatever
  swift-crypto 5.x requires; it is not added as a direct dependency.
- `Package.resolved` is committed and must pin swift-crypto 5.x (>= 5.0.3).
  Refresh it with `swift package update swift-crypto` only, so unrelated pins
  do not change.
- Crypto usage is limited to three call sites:
  - `Sources/XGatewayCore/OAuth1.swift`: `HMAC<Insecure.SHA1>` with `SymmetricKey`
    (OAuth 1.0a signature)
  - `Sources/XGatewayCore/XGatewayOAuth2.swift`: `SHA256.hash` (PKCE S256)
  - `Sources/XGatewayCore/XGatewayResourceUsage.swift`: `SHA256.hash` (resource
    id hash)
- Import boundary: OAuth1 and OAuth2 keep `#if canImport(CryptoKit)` /
  `import Crypto`. XGatewayResourceUsage keeps its unconditional
  `import Crypto`. Change this split only if swift-crypto 5 fails to compile
  without the change. Do not add wrapper or abstraction layers.
- Output invariant: hashing and signing output stays byte-for-byte identical.
  These pinned expectations are the acceptance oracle and must not be edited:
  `Tests/XGatewayCoreTests/XGatewayCoreTests.swift` (HMAC-SHA1 and the RFC 7636
  PKCE vector `E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM`),
  `Sources/XGatewaySwiftSmokeTests/main.swift` (OAuth1 header signature
  `tR3%2BTy81lMeYAr%2FFid0kMTYa%2FWM%3D`), and
  `Sources/XGatewaySwiftSmokeTests/OAuth2SmokeTests.swift`.
- Toolchain and platform floor: the root package stays at
  `swift-tools-version: 5.8` and `.macOS(.v13)`. swift-crypto 4.5.2 already
  declares `swift-tools-version:6.1` with no `platforms` floor, so the local
  toolchain is at least 6.1.
  - If swift-crypto 5.x needs a newer compiler than the local toolchain, report
    it as a blocker and stop. Do not install another toolchain.
  - If SwiftPM refuses the root 5.8 tools-version, raise it only to the minimum
    accepted value and record that as a finding.
  - If 5.x requires a macOS deployment target above 13, report it as a blocker
    that needs a maintainer decision. Do not raise `.macOS(.v13)` on your own.
- Upgrade blocker rule: if any dependency caps swift-crypto below 5, report the
  exact constraint as a blocker and make no workaround.
- Verification: `swift package update swift-crypto`, `swift build`,
  `swift test`, `mise run test`, and `mise run lint`. If swiftlint is not
  installed, report lint as unavailable and include the evidence. On macOS the
  OAuth1/OAuth2 CryptoKit branch hides the Linux `import Crypto` path. A Linux
  build is not required for acceptance; if none runs, record it as a
  verification gap.

## Versioning and Tagging

- The package version lives in two places that must match: `VERSION` and the
  `"version"` value in `Sources/XGatewayCore/XGatewayCore.swift` (the `version`
  group). A dependency-only change bumps the patch version
  (`0.1.26` -> `0.1.27`) in the same final commit.
- Push order: push the final commit to `origin/main`, then create tag
  `v<VERSION>` on that exact pushed commit and push only that tag. Creating a
  GitHub release and publishing Homebrew, npm, or Nix are separate maintainer
  steps and are not part of a dependency upgrade.

## Release Surfaces

- Homebrew formula archives under `dist/homebrew/`
- Signed and notarized Cask DMGs under `dist/homebrew-cask/`
