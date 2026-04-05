# X Gateway Usage Tweets Baseline Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#capability-matrix-implementation-target`
**Created**: 2026-04-05
**Last Updated**: 2026-04-05

---

## Design Document Reference

**Source**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`

### Summary
Add a reviewed stable capability for X API post-usage inspection using `GET /2/usage/tweets`. The feature should expose usage counts, not an inferred dollar-cost estimate, because current X billing documentation keeps per-endpoint pricing in the Developer Console rather than a public billing API.

### Scope
**Included**:
- stable `usage.tweets` capability metadata and planner wiring
- bearer-backed REST adapter for `GET /2/usage/tweets`
- SDK surface for retrieving usage counts
- CLI surface for `usage tweets`
- canonical project-owned GraphQL query field for usage retrieval
- regression coverage for SDK, CLI, GraphQL, and metadata alignment

**Excluded**:
- direct billing-dollar retrieval
- Developer Console scraping or non-public billing integrations
- generalized usage endpoints beyond tweet/post consumption

---

## Tasks

### TASK-001: Stable Capability Contract
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/capability-metadata.ts`
- `src/stable-capability-executor.ts`
- `src/lib.ts`

**Completion Criteria**:
- [x] `usage.tweets` is registered as an implemented stable read capability
- [x] planner/auth metadata truthfully advertises bearer-only support
- [x] SDK types and client method expose normalized usage data

### TASK-002: Bearer REST Adapter And Public Surfaces
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/capability-adapters.ts`
- `src/cli.ts`
- `src/public-graphql-schema.ts`
- `src/public-api-contract.ts`

**Completion Criteria**:
- [x] reviewed adapter calls `GET /2/usage/tweets`
- [x] CLI exposes `usage tweets [--days <n>]`
- [x] canonical `api request` supports the usage query field

### TASK-003: Verification
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`

**Completion Criteria**:
- [x] tests cover SDK, CLI, GraphQL, and metadata alignment
- [x] `bun run test` passes
- [x] `bun run typecheck` passes
- [x] `bun run build` passes

---

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Usage capability contract | `src/capability-metadata.ts`, `src/stable-capability-executor.ts`, `src/lib.ts` | COMPLETED | Covered |
| Usage adapter and public surfaces | `src/capability-adapters.ts`, `src/cli.ts`, `src/public-graphql-schema.ts`, `src/public-api-contract.ts` | COMPLETED | Covered |
| Regression coverage | `src/lib.test.ts` | COMPLETED | Covered |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001, TASK-002 |

## Completion Criteria

- [x] Stable CLI, SDK, and canonical project-owned GraphQL surfaces expose usage-count retrieval
- [x] The feature remains truthful that it returns usage counts rather than dollar billing totals
- [x] Verification passes for metadata, public contract, and runtime behavior

## Progress Log

### Session: 2026-04-05 14:55 JST
**Tasks Completed**: None yet
**Tasks In Progress**: TASK-001
**Blockers**: None
**Notes**:
- Current X documentation exposes `GET /2/usage/tweets` for daily post consumption counts and points users to the Developer Console for live costs/pricing.
- The implementation will therefore ship a stable usage-count capability, not a speculative cost calculator.

### Session: 2026-04-05 15:20 JST
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Added `usage.tweets` as a bearer-only stable capability with SDK, CLI, and canonical public GraphQL exposure.
- Verification passed with `bun test`, `bun run typecheck`, and `bun run build`.
