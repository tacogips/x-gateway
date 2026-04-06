# X Gateway API Usage Surface Alignment Implementation Plan

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
Align the stable usage capability with the naming users expect by exposing `apiUsage` instead of the misleading `postUsage` GraphQL field, while keeping the implementation truthful that the route returns usage counts and caps rather than exact billed dollars. Harden the usage adapter so current upstream `/2/usage/tweets` responses with omitted daily breakdowns still normalize successfully.

### Scope
**Included**:
- stable public GraphQL rename from `postUsage` to `apiUsage`
- stable capability metadata alignment for the usage capability public operation name
- clearer validation guidance when callers still use `postUsage`
- tolerant usage payload normalization for string numerics and missing daily breakdown fields
- regression coverage updates for schema, metadata, CLI GraphQL, and live-shape payload handling
- public skill example updates for the renamed field

**Excluded**:
- direct billing-dollar retrieval from the Developer Console
- browser automation or scraping for console-only billing totals
- changes to the underlying capability id `usage.tweets`

---

## Tasks

### TASK-001: Public Contract Rename
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/public-graphql-schema.ts`
- `src/public-graphql-contract.ts`
- `src/capability-metadata.ts`

**Completion Criteria**:
- [x] Stable public GraphQL field is `apiUsage`
- [x] `postUsage` returns an explicit migration error directing callers to `apiUsage`
- [x] Capability metadata advertises `apiUsage` as the stable public operation name

### TASK-002: Usage Adapter Hardening
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/capability-adapters.ts`
- `src/lib.ts`

**Completion Criteria**:
- [x] Usage normalization accepts integer strings returned by the upstream endpoint
- [x] Missing daily usage breakdown fields normalize to empty collections instead of failing
- [x] Returned result shape remains stable for the public GraphQL contract

### TASK-003: Verification And Public Examples
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`
- `.agents/skills/x-read-via-reader/SKILL.md`

**Completion Criteria**:
- [x] Regression tests cover `apiUsage` and deprecated `postUsage`
- [x] Regression tests cover the currently observed upstream usage payload shape
- [x] Public example usage shows `apiUsage`
- [x] `bun test`, `bun run typecheck`, and `bun run build` pass

---

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Public usage contract rename | `src/public-graphql-schema.ts`, `src/public-graphql-contract.ts`, `src/capability-metadata.ts` | COMPLETED | Covered |
| Usage adapter normalization | `src/capability-adapters.ts`, `src/lib.ts` | COMPLETED | Covered |
| Verification and docs | `src/lib.test.ts`, `.agents/skills/x-read-via-reader/SKILL.md` | COMPLETED | Covered |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001, TASK-002 |

## Completion Criteria

- [x] Stable GraphQL usage lookup is named `apiUsage`
- [x] Deprecated `postUsage` calls fail with a migration-oriented error
- [x] Current upstream `/2/usage/tweets` payload shape normalizes successfully
- [x] Verification passes for tests, type checking, and build output

## Progress Log

### Session: 2026-04-05 19:50 JST
**Tasks Completed**: None yet
**Tasks In Progress**: TASK-001
**Blockers**: None
**Notes**:
- Live testing showed the upstream usage endpoint currently returns string numerics and may omit `daily_client_app_usage` and `daily_project_usage`.
- The public `postUsage` field name was judged misleading for users who expect general API usage rather than post-specific wording.

### Session: 2026-04-05 20:01 JST
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Renamed the stable public GraphQL usage field to `apiUsage` and changed `postUsage` into a migration-oriented validation error.
- Hardened usage normalization to accept string numerics and omitted daily breakdowns from the current upstream `/2/usage/tweets` payload.
- Verification passed with `bun test`, `bun run typecheck`, and `bun run build`, and the live `taco-x` query succeeded through both CLI surfaces.

## Related Plans

- **Previous**: `impl-plans/completed/x-gateway-usage-tweets-baseline.md`
- **Next**: None
- **Depends On**: `impl-plans/completed/x-gateway-usage-tweets-baseline.md`
