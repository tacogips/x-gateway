# Architecture Design

This document defines the architecture for `x-gateway` as both CLI and library.

## Overview

`x-gateway` is a dual-surface TypeScript system with two CLI binaries:

- Surface A1: AI-first full CLI (`x-gateway ...`) for the project-owned GraphQL contract plus local diagnostics and capability inspection
- Surface A2: AI-first read-only CLI (`x-gateway-reader ...`) for query-only access to that same project-owned contract plus local diagnostics and capability inspection
- Surface B: programmatic SDK/library API

Both surfaces share one core service layer so behavior is consistent for auth, retries, rate handling, and error semantics.

Policy decision:

- Write operations are enforced as unavailable in `x-gateway-reader` at command-dispatch time.
- Rejected write operations return deterministic `UNSUPPORTED` errors with explicit remediation (`use x-gateway`).
- The primary public interface is the project-owned GraphQL request path (`graphql query <query>` in CLI and `createXGatewayClient().graphqlQuery({ query })` in the SDK).
- Stable SDK helpers may remain when they dispatch through the same reviewed capability executor, but the public CLI no longer exposes transitional convenience command groups as peer surfaces.
- Transport choice is internal: use REST where it is stable and compatible with configured auth, and use X web GraphQL only where a capability requires it.
- Unsupported capabilities must be rejected at the boundary with explicit guidance instead of being advertised as generally available.
- Capability docs must not overclaim bearer support when the repository does not yet provide a reviewed user-context flow for that operation.

## Architectural Layers

1. Interface Layer
- CLI command parser, argument validation, output renderer
- Library exports with typed capability APIs, project-owned GraphQL request/response contracts, and local diagnostics helpers

2. Application Layer
- Capability-level input validation and capability gating
- Use-case services expose stable operations such as account lookup and post creation
- Public GraphQL request parsing and request-to-capability planning
- Limited nested capability execution for reviewed child fields such as `Post.replies(...)`
- Orchestration for chained operations chooses internal adapters per capability
- Unsupported command-group detection so callers fail before assuming a non-existent mapping exists

3. Capability Adapter Layer
- Capability-specific adapters map the stable product contract onto one or more upstream transports
- Adapter selection depends on auth mode, endpoint availability, and maturity of the transport mapping
- When multiple credential families are configured at once, adapter selection must be capability-specific rather than globally pinned to one auth family
- Read adapters and stable posting adapters must remain separate contracts so unsupported auth families cannot retain latent mutation methods behind a shared interface
- REST/v1.1 or v2 endpoints are preferred for OAuth1-compatible flows when they provide stable coverage
- X web GraphQL is used only for capabilities that cannot be served reliably through public REST endpoints

4. Gateway Layer
- HTTP transport, auth injectors, retry policy, pagination helpers
- Request/response normalization across X API endpoints
- GraphQL response parsing that accepts standard JSON and `application/*+json` media types used by GraphQL servers

### Network Retry and Backoff Policy

- Transport layer must implement retry with exponential backoff + jitter as default.
- Retry targets: network timeouts, DNS/connection failures, and retryable upstream 5xx/429 responses.
- Backoff parameters are configurable via CLI options, SDK parameters, and `X_GW_` env vars.
- Respect provider `Retry-After` when present; otherwise compute delay from configured backoff strategy.
- Mutating operations must use idempotency controls where available before retrying.
- Retry exhaustion must emit a detailed diagnostic including attempts, elapsed time, and final error classification.

5. Error Intelligence Layer
- Maps API/HTTP/runtime failures to typed domain errors
- Generates human-readable and AI-actionable diagnostic payloads

6. Configuration Layer
- Merged resolution from env vars + explicit parameter objects
- Validation with actionable error reports

## Core Design Decisions

### Shared Engine for CLI and Library

- CLI commands call the same internal service methods exposed for library consumers.
- No separate logic branches for equivalent operations.

### Stable Contract with Internal Adapters

- The stable product contract is capability-oriented: the canonical public interface describes user intent, not X internal transport details.
- The canonical public interface is a project-owned GraphQL schema rather than a passthrough of raw X web GraphQL, and the CLI namespace should expose that contract directly as `graphql`.
- Each exposed capability must declare its supported auth modes, transport strategy, and known limitations in the capability registry.
- Each capability/inventory entry must also declare its surface category so stable contract operations and deferred capabilities are distinguishable in one place.
- The capability planner is the authoritative layer that maps public operations such as `accountMe` or `createPost` to capability ids such as `account.me` and `post.create`.
- Planner logic should be explicit in code: a project-owned public-operation registry maps request fields to capabilities, and a separate reviewed route registry selects auth family plus transport per capability.
- Registry coherence is part of the architecture, not just a test convenience: project-owned public field names must stay in sync with capability metadata, and implemented stable capabilities must stay aligned across metadata, route planning, and executor dispatch.
- Stable capability execution should also be registry-driven: once a capability id is selected, CLI helpers, SDK methods, and the public GraphQL contract should dispatch through the same internal execution registry instead of maintaining per-entrypoint switch statements.
- Nested public GraphQL capability execution is intentionally exceptional and reviewed field-specific in the current architecture. `Post.replies(...)` may trigger bounded recursive execution through the same stable capability registry, while other nested fields remain projection-only unless explicitly designed.
- Route order matters and must be data-driven rather than hidden in helper branching. Example: `post.get` may prefer OAuth1 REST while still declaring bearer REST as a reviewed fallback.
- When both bearer and OAuth1 credentials are available, each capability should choose its reviewed auth path independently instead of letting one credential family shadow the other globally.
- A reviewed adapter path counts as implemented only when the corresponding auth/transport contract is enforced in code, not merely mentioned in capability docs or left behind as unused methods.
- Error diagnostics should identify the reviewed route that actually ran, including both transport family and auth family, so operators can distinguish `rest-v1/oauth1`, `rest-v2/bearer`, and `graphql-web/bearer` failures.
- A convenience command or SDK helper is considered implemented only when it is backed by a reviewed adapter contract and tests.
- The CLI may expose local/non-network diagnostics (`health`, `version`, capability inspection, auth configuration diagnostics) even when no live transport is configured.

### Configuration Precedence

Default precedence (overridable):
1. explicit function/command parameters
2. process environment
3. defaults

This enables library embedding in multi-tenant systems without global environment mutation.

### Environment Variable Namespace

- All project-defined environment keys must use `X_GW_` prefix.
- Example keys: `X_GW_TOKEN`, `X_GW_ACCESS_TOKEN`.
- Legacy `X_` keys are out of design scope unless an explicit compatibility shim is approved.
- The stable configuration surface does not accept generic API-base aliases such as `apiBaseUrl`, `--api-base-url`, or `X_GW_API_BASE_URL`.
- `X_GW_CONFIG_MODE` is the canonical config-resolution variable.
- `X_GW_AUTH_MODE` is reserved for legacy auth-type shells (`oauth1` or `bearer`) and must not be overloaded as the stable config-resolution variable going forward.

### Auth Mode Abstraction

Support multiple auth flows through one interface:

- OAuth 2.0 bearer token
- OAuth 1.0a user context
- future extension: OAuth 2.0 PKCE refresh/session helpers

### Deterministic Error Model

All failures map to stable internal codes. Messages include probable root cause and remediation guidance.

## Capability Matrix (Implementation Target)

The long-term implementation target remains broad coverage of X API capabilities available to the configured app tier and scopes. Delivery is capability-by-capability rather than transport-first:

- Phase 1: restore practical OAuth1-compatible operations through stable REST-backed adapters for the highest-value flows
- Phase 1 current baseline: `account.me`, `post.get`, `post.replies`, `post.create`, `post.delete`, `post.reply`, `post.quote`, `post.repost`, and `post.unrepost`
- Phase 1 canonical public GraphQL fields: `accountMe`, `post`, `createPost`, `deletePost`, `replyToPost`, `quotePost`, `repostPost`, and `unrepostPost`
- Direct reply listing is part of the stable contract through `post.replies`, implemented as direct-reply recent search and exposed canonically through nested `Post.replies(...)`.
- Recursive reply expansion is also supported through `Post.replies(...)`, using bounded nested execution on top of the same stable `post.replies` capability.
- Followed-account latest-post retrieval is part of the stable read contract through `timeline.following`, exposed canonically as `followingTimeline(...)`. It is intentionally modeled as a bounded project-owned aggregate: read the authenticated account follow graph, fetch recent user timelines for followed accounts, merge posts by recency, and return the same `PostPage` payload shape used by other timeline reads.
- `timeline.following` must not request owner-only tweet metric fields such as `organic_metrics` or `promoted_metrics` when fetching followed-account timelines. Those fields can cause otherwise readable other-user timelines to return upstream errors and empty pages. The aggregate should request public fields only, preserve public metrics, and let `metrics.impressionCount` remain `null` when no reviewed public source is available.
- Phase 1 canonical mutation baseline includes inline image attachments for `createPost`, `replyToPost`, and `quotePost` through project-owned attachment input that maps onto internal OAuth1 media upload plus stable REST posting
- `likes.list` remains deferred until a reviewed live route is verified; it is intentionally not part of the canonical public GraphQL contract in the current repository state
- Phase 2: add GraphQL-backed adapters where public REST does not cover the required behavior
- Phase 3: expand additional capability families through the same project-owned contract without reintroducing raw upstream GraphQL as a peer public surface unless a new design decision explicitly approves it

Target capability families:

- post create/delete/reply/quote/repost
- media upload and attach
- likes, bookmarks, engagement toggles
- user/profile lookup
- timelines and mentions
- followers/following traversal
- thread/referenced-content expansion
- account identity and auth introspection
- direct message operations where supported by credentials/tier

## Posting Pattern Handling

Publishing subsystem must model these patterns as first-class operations:

- simple text post
- delete post
- reply post (with parent linkage)
- quote post (with quoted post linkage)
- repost/undo repost
- post with image media
- post with video media
- article/long-form publish path where API supports it
- retrieval and expansion of referenced/original posts
- retrieval of stable post metrics with nullable fields when upstream access is partial

## Error Classification Model

Primary categories:

- `VALIDATION_ERROR`
- `AUTH_MISSING`
- `AUTH_INVALID`
- `AUTH_EXPIRED`
- `AUTH_REVOKED`
- `PERMISSION_DENIED`
- `RATE_LIMITED`
- `RESOURCE_NOT_FOUND`
- `CONFLICT`
- `UPSTREAM_FAILURE`
- `NETWORK_FAILURE`
- `INTERNAL_ERROR`

Each category provides:

- user-facing summary
- technical detail
- likely causes
- remediation steps
- retryability hint
- retry policy context (whether retried, delays applied, reason retry stopped)

## Module Boundaries (Planned)

- `src/cli.ts` command definitions and output formatting
- `src/lib.ts` public SDK exports, config resolution, diagnostics, shared stable-capability execution, and temporary adapter composition
- `src/capability-metadata.ts` capability registry rows plus reviewed route-planning metadata
- `src/public-graphql-parser.ts` project-owned GraphQL document parsing for the stable public contract
- `src/public-graphql-contract.ts` project-owned GraphQL field registry, request-to-capability mapping, and response projection helpers
- `src/capability-runtime.ts` reviewed route selection, auth-readiness derivation, and planner-to-adapter execution wiring
- `src/stable-capability-executor.ts` stable capability execution registry plus shared dispatch used by direct SDK helpers and the project-owned GraphQL surface
- `src/capability-adapters.ts` reviewed REST capability adapters plus transport-specific response-mapping helpers for the stable baseline
- Current implementation note: the public contract, planner/runtime, stable execution, and reviewed REST adapter layer now have dedicated modules. `src/lib.ts` still composes them and owns shared retry/config/error helpers.
- Current implementation note: the first hardening step kept one shared execution registry inside `src/lib.ts` so capability dispatch is not duplicated across CLI, SDK, and public GraphQL entrypoints.
- Current implementation note: planner metadata, public-contract parsing, and the public request mapper now have dedicated modules.
- Current implementation note: capability runtime planning now lives in `src/capability-runtime.ts`, so `src/lib.ts` no longer owns route selection and auth-readiness assembly directly.
- Current implementation note: stable capability execution now lives in a dedicated module so `src/lib.ts` no longer owns the registry-driven dispatch layer directly.
- Current implementation note: reviewed REST capability adapters now live in `src/capability-adapters.ts`.
- Current implementation note: the public GraphQL parser now accepts list and object literals for project-owned input objects such as post attachments while still rejecting variables, fragments, aliases, directives, and multi-field documents.
- Current implementation target: `followingTimeline` must complete the existing partial registry/schema work by adding the reviewed adapter and tests that prove the public GraphQL field, stable capability executor, capability metadata, SDK types, and PostPage projection all remain coherent.
- Future extractions when complexity warrants:
  - `src/public-contract/` for project-owned GraphQL parsing and projection
  - `src/planner/` for capability planning and transport/auth routing
  - `src/capabilities/` for stable use-case interfaces
  - `src/adapters/` for REST/GraphQL capability adapters
  - `src/gateway/x-api/` for shared transport concerns
  - `src/errors/` and `src/config/` for focused infrastructure modules

## Swift Port Architecture

The Swift port is introduced as a Swift Package Manager package that can
coexist with the TypeScript implementation during migration. The package owns
three first-slice products:

- `XGatewayCore`: Swift library target for config resolution, command parsing,
  error envelopes, public GraphQL operation classification, capability metadata,
  and CLI execution helpers.
- `x-gateway-read`: read-only executable product. It accepts stable read
  commands and rejects GraphQL mutations before execution.
- `x-gateway-write`: write-oriented executable product. It accepts write
  commands and rejects GraphQL queries before execution.

The package boundary is intentionally product-oriented rather than a single
monolithic executable so downstream installers can build, package, and install
only the read or write command. The initial migration slices keep the public
CLI contract stable for local diagnostics (`health`, `version`, `auth`,
`capabilities`, `graphql schema`), enforce read/write GraphQL separation, and
provide a live transport baseline for `accountMe`, `post`, `apiUsage`,
`searchPosts`, `homeTimeline`, `followingTimeline`, `userTimeline`,
`mentionsTimeline`, `createPost`, `deletePost`, `replyToPost`, `quotePost`,
`repostPost`, and `unrepostPost`. Non-usage Swift live requests prefer OAuth1
signing when complete OAuth1 credentials are configured and fall back to bearer
tokens; `apiUsage` remains bearer-token only. Swift read projections include
stable metrics, author profiles, media asset URLs, and referenced-post
shortcuts when upstream expansions are present, and honor `includePromoted` by
filtering promoted posts by default when upstream promotion metrics identify
them. Swift read fields also honor `mediaRootDir`, `downloadMedia`, and
`forceDownload`, materializing media under `mediaRootDir/<post-id>/` while
reusing existing files unless a forced refresh is requested. Swift also hydrates
bounded nested `Post.replies(...)` selections through the same read transport
and reply-search capability path. Remaining live X API transport details should
be ported capability-by-capability behind `XGatewayCore` without changing the
two executable products. Swift
attachment-backed `createPost`, `replyToPost`, and `quotePost` mutations
require OAuth1, upload image attachments through the X media upload API, apply
alt text when provided, and include uploaded `media_ids` in the v2 tweet body.

Swift command output must preserve the existing structured `ok` envelope and
remediation-oriented error payloads so AI agent callers receive the same
operational diagnostics as the TypeScript CLI.

## Test Strategy (High Level)

- unit tests for config validation and error mapping
- unit tests for post pattern payload construction
- contract tests for gateway request generation
- integration tests against mocked X API responses
- optional live smoke tests gated by explicit credentials/env
