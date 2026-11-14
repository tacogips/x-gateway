# X Gateway Public Request Planner Extraction Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#module-boundaries-planned`
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/design-public-graphql-contract.md`

### Summary
The repository already had a project-owned GraphQL parser and capability metadata, but the request-to-capability mapper and response projection logic still lived inside `src/lib.ts`. This plan extracts that public request-planning layer into its own module so the stable public contract is enforced separately from capability execution and upstream adapters.

### Scope
**Included**:
- extract the project-owned GraphQL field registry and request planner into a dedicated module
- extract public response projection helpers into the same module
- add regression coverage proving raw X-style fields are rejected by the stable public contract

**Excluded**:
- moving stable capability execution out of `src/lib.ts`
- moving REST/GraphQL adapter implementations out of `src/lib.ts`
- adding new capabilities or transport routes

---

## Tasks

### TASK-001: Public Request Planner Module
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/public-api-contract.ts`
- `src/lib.ts` refactor to consume the extracted planner

**Completion Criteria**:
- [x] Public GraphQL field registry no longer lives in `src/lib.ts`
- [x] Request-to-capability mapping is enforced by a dedicated module
- [x] Response projection for the stable public contract is reused through that module

### TASK-002: Regression Coverage
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`

**Completion Criteria**:
- [x] Tests continue to cover the stable public GraphQL contract
- [x] A regression test rejects raw X-shaped fields on the stable public contract

### TASK-003: Documentation and Verification
**Status**: Completed
**Parallelizable**: No (depends on TASK-001, TASK-002)
**Deliverables**:
- `design-docs/specs/architecture.md`
- repository verification via typecheck, tests, and build

**Completion Criteria**:
- [x] Architecture docs mention the extracted public request-planner module
- [x] `bun run typecheck` passes
- [x] `bun test` passes
- [x] `bun run build` passes

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Public request planner | `src/public-api-contract.ts` | COMPLETED | Passed |
| Library integration | `src/lib.ts` | COMPLETED | Passed |
| Regression coverage | `src/lib.test.ts` | COMPLETED | Passed |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001, TASK-002 |

## Completion Criteria

- [x] The project-owned public request mapper is separated from the adapter integration layer
- [x] Stable public GraphQL request handling rejects raw X-shaped fields explicitly
- [x] Verification passes after the extraction

## Progress Log

### Session: 2026-03-08 23:45
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Architecture review found the repository already aligned with the intended product direction at the behavior level, but the public request mapper was still embedded in `src/lib.ts`.
- Extracted the stable public GraphQL field registry, request-to-capability mapping, and response projection into `src/public-api-contract.ts`.
- Added regression coverage to ensure raw X-style field names remain invalid on the stable public contract.
- Re-ran `bun run typecheck`, `bun test`, and `bun run build`.
