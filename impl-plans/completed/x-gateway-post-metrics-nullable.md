# X Gateway Post Metrics Nullable Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/design-post-metrics.md
**Created**: 2026-04-05
**Last Updated**: 2026-04-05

---

## Design Document Reference

**Source**:
- design-docs/specs/design-post-metrics.md
- design-docs/specs/design-public-graphql-contract.md
- design-docs/specs/architecture.md
- design-docs/specs/command.md

### Summary
Add stable nullable post metrics to post-shaped GraphQL payloads so callers can request counts such as likes and impressions without failing when some metric sources are unavailable.

### Scope
**Included**:
- stable `PostMetrics` type in the public GraphQL schema
- shared post payload model updates in the SDK types
- adapter mapping from upstream metric fields into nullable stable metrics
- regression coverage for populated and null metric cases
- design and progress tracking updates

**Excluded**:
- new capability ids
- additional upstream calls to backfill missing metrics
- metric-specific auth probing or retries

---

## Tasks

### TASK-001: Metrics Design
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `design-docs/specs/design-post-metrics.md`
- related contract/design updates

**Completion Criteria**:
- [x] Stable metrics shape is documented
- [x] Nullability behavior is specified
- [x] No-new-capability boundary is explicit

### TASK-002: Schema, Types, and Adapter Mapping
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/public-graphql-schema.ts`
- `src/lib.ts`
- `src/capability-adapters.ts`

**Completion Criteria**:
- [x] Post-shaped schema types expose `metrics`
- [x] Stable TypeScript post types expose `metrics`
- [x] Adapter mapping returns nullable metric fields instead of throwing

### TASK-003: Verification and Tracking
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`
- `impl-plans/README.md`
- `impl-plans/PROGRESS.json`

**Completion Criteria**:
- [x] Positive metric coverage exists
- [x] Null metric coverage exists
- [x] Typecheck, tests, and build pass

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Metrics design | `design-docs/specs/design-post-metrics.md` | COMPLETED | N/A |
| Schema and SDK types | `src/public-graphql-schema.ts`, `src/lib.ts` | COMPLETED | Covered |
| Adapter mapping | `src/capability-adapters.ts` | COMPLETED | Covered |
| Verification | `src/lib.test.ts` | COMPLETED | Covered |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-002 |

## Completion Criteria

- [x] Stable post payloads expose metrics through the project-owned GraphQL contract
- [x] Missing upstream metric access becomes `null` at the field level
- [x] Verification passes across SDK, CLI-level contract tests, typecheck, and build

## Progress Log

### Session: 2026-04-05 19:52 JST
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Added a stable nested `metrics` object on post-shaped payloads instead of scattering metric fields directly on `Post`.
- Kept the metrics object always present while making individual metric values nullable so partial upstream access does not fail the request.
- Reused existing stable post capabilities rather than introducing a new metrics-specific capability.
