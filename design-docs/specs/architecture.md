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
- `XGatewaySwiftSmokeTests`: executable smoke-test harness used by `task test`.

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

## Release Surfaces

- Homebrew formula archives under `dist/homebrew/`
- Signed and notarized Cask DMGs under `dist/homebrew-cask/`
