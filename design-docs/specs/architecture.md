# Architecture Design

This document defines the architecture for `x-gateway` as both CLI and library.

## Overview

`x-gateway` is a dual-surface TypeScript system:

- Surface A: AI-first CLI (`x-gateway ...`)
- Surface B: programmatic SDK/library API

Both surfaces share one core service layer so behavior is consistent for auth, retries, rate handling, and error semantics.

## Architectural Layers

1. Interface Layer
- CLI command parser, argument validation, output renderer
- Library exports with typed request/response contracts

2. Application Layer
- Use-case services per capability (posts, timelines, users, media, engagement, DMs)
- Orchestration for chained operations (upload media then post, fetch quote origin, thread traversal)

3. Gateway Layer
- HTTP transport, auth injectors, retry policy, pagination helpers
- Request/response normalization across X API endpoints

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

### Configuration Precedence

Default precedence (overridable):
1. explicit function/command parameters
2. process environment
3. defaults

This enables library embedding in multi-tenant systems without global environment mutation.

### Auth Mode Abstraction

Support multiple auth flows through one interface:

- OAuth 2.0 bearer token
- OAuth 1.0a user context
- future extension: OAuth 2.0 PKCE refresh/session helpers

### Deterministic Error Model

All failures map to stable internal codes. Messages include probable root cause and remediation guidance.

## Capability Matrix (Implementation Target)

The implementation target is broad coverage of X API capabilities available to the configured app tier and scopes:

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

## Module Boundaries (Planned)

- `src/cli/` command definitions and output formatting
- `src/lib/` public SDK exports and request types
- `src/core/` service interfaces and use-case logic
- `src/gateway/x-api/` transport/auth/pagination adapters
- `src/errors/` error taxonomy and message composer
- `src/config/` env+parameter config loader and validation

## Test Strategy (High Level)

- unit tests for config validation and error mapping
- unit tests for post pattern payload construction
- contract tests for gateway request generation
- integration tests against mocked X API responses
- optional live smoke tests gated by explicit credentials/env
