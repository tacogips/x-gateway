# Architecture Design

This document defines the architecture for `x-gateway` as both CLI and library.

## Overview

`x-gateway` is a dual-surface TypeScript system with two CLI binaries:

- Surface A1: AI-first full CLI (`x-gateway ...`) for GraphQL query + mutation workflows
- Surface A2: AI-first read-only CLI (`x-gateway-reader ...`) for GraphQL query workflows
- Surface B: programmatic SDK/library API

Both surfaces share one core service layer so behavior is consistent for auth, retries, rate handling, and error semantics.

Policy decision:

- Write operations are enforced as unavailable in `x-gateway-reader` at command-dispatch time.
- Rejected write operations return deterministic `UNSUPPORTED` errors with explicit remediation (`use x-gateway`).
- Raw GraphQL operation input is the primary supported network contract for both CLI and SDK surfaces.
- Unmapped high-level endpoint wrappers are not part of the stable public surface; they must be rejected at the CLI boundary instead of being advertised as available.

## Architectural Layers

1. Interface Layer
- CLI command parser, argument validation, output renderer
- Library exports with typed GraphQL request/response contracts plus local diagnostics helpers

2. Application Layer
- GraphQL operation input validation and capability gating
- Use-case services per capability only after a concrete GraphQL mapping is defined
- Orchestration for chained operations only after underlying GraphQL operations are available
- Unsupported command-group detection so callers fail before assuming a non-existent mapping exists

3. Gateway Layer
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

4. Error Intelligence Layer
- Maps API/HTTP/runtime failures to typed domain errors
- Generates human-readable and AI-actionable diagnostic payloads

5. Configuration Layer
- Merged resolution from env vars + explicit parameter objects
- Validation with actionable error reports

## Core Design Decisions

### Shared Engine for CLI and Library

- CLI commands call the same internal service methods exposed for library consumers.
- No separate logic branches for equivalent operations.

### GraphQL-First Contract

- The stable cross-surface contract is `operationName` plus either `documentId` or inline `query`.
- Optional structured inputs are `variables`, `features`, and `fieldToggles`.
- CLI and SDK must treat this raw GraphQL request shape as first-class, not as an escape hatch.
- A convenience command or SDK helper is considered implemented only when it is backed by a reviewed GraphQL mapping artifact.
- Capability-registry rows outside raw GraphQL transport are planning/diagnostic metadata, not proof that a high-level helper exists.
- Until such mappings exist, the stable SDK surface is `request`, configuration resolution, auth diagnostics, and capability inspection.
- The CLI may expose local/non-network diagnostics (`health`, `version`, capability inspection, auth configuration diagnostics) even when no GraphQL mapping exists.

### Configuration Precedence

Default precedence (overridable):
1. explicit function/command parameters
2. process environment
3. defaults

This enables library embedding in multi-tenant systems without global environment mutation.

### Environment Variable Namespace

- All project-defined environment keys must use `X_GW_` prefix.
- Example keys: `X_GW_TOKEN`, `X_GW_ACCESS_TOKEN`, `X_GW_GRAPHQL_BASE_URL`.
- Legacy `X_` keys are out of design scope unless an explicit compatibility shim is approved.
- The stable configuration surface does not accept generic API-base aliases such as `apiBaseUrl`, `--api-base-url`, or `X_GW_API_BASE_URL`.

### Auth Mode Abstraction

Support multiple auth flows through one interface:

- OAuth 2.0 bearer token
- OAuth 1.0a user context
- future extension: OAuth 2.0 PKCE refresh/session helpers

### Deterministic Error Model

All failures map to stable internal codes. Messages include probable root cause and remediation guidance.

## Capability Matrix (Implementation Target)

The long-term implementation target remains broad coverage of X API capabilities available to the configured app tier and scopes, but the current GraphQL-only pivot changes delivery sequencing:

- Phase 1: raw GraphQL request transport, capability registry, and accurate unsupported guidance
- Phase 2+: high-level helpers only after concrete GraphQL mappings are checked into the repository

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
- reply post (with parent linkage)
- quote post (with quoted post linkage)
- repost/undo repost
- post with image media
- post with video media
- article/long-form publish path where API supports it
- retrieval and expansion of referenced/original posts

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
- `src/lib.ts` public SDK exports, GraphQL request types, GraphQL-base config resolution, and local diagnostics helpers
- Future extractions when complexity warrants: `src/core/`, `src/gateway/x-api/`, `src/errors/`, and `src/config/`

## Test Strategy (High Level)

- unit tests for config validation and error mapping
- unit tests for post pattern payload construction
- contract tests for gateway request generation
- integration tests against mocked X API responses
- optional live smoke tests gated by explicit credentials/env
