# X Gateway Raw GraphQL Isolation Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#module-boundaries-planned`
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`
- `design-docs/specs/design-public-graphql-contract.md`

### Summary
The repository now has a stable capability planner plus a project-owned GraphQL-shaped public contract, but the raw GraphQL escape hatch still lived inside `src/lib.ts`. This plan isolates low-level raw GraphQL execution into a dedicated module so the stable public contract and the low-level escape hatch remain separate in code as well as in documentation.

### Scope
**Included**:
- dedicated raw GraphQL requester module for validation, auth enforcement, HTTP execution, and response normalization
- `src/lib.ts` composition changes so the client wires stable capability execution and raw GraphQL separately
- design and implementation-plan updates describing the dedicated escape-hatch module

**Excluded**:
- changing the raw GraphQL user-facing contract
- adding new capabilities or adapter routes
- moving retry/config/error infrastructure out of `src/lib.ts`

---

## Tasks

### TASK-001: Extract Raw GraphQL Requester
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/raw-graphql-client.ts`
- `src/lib.ts`

**Completion Criteria**:
- [x] Raw GraphQL request validation and HTTP execution live outside `src/lib.ts`
- [x] Bearer-only auth enforcement for the escape hatch remains unchanged
- [x] Stable capability execution no longer shares the same implementation block as raw GraphQL request execution

### TASK-002: Document Escape-Hatch Isolation
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`
- `design-docs/specs/design-public-graphql-contract.md`

**Completion Criteria**:
- [x] Architecture docs identify raw GraphQL as a dedicated low-level module
- [x] Command/docs continue to describe `graphql request` as an advanced escape hatch only
- [x] Public-contract docs state that the stable contract does not reuse the raw requester implicitly

### TASK-003: Verification
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`
- `src/capability-adapters.test.ts`

**Completion Criteria**:
- [x] Existing raw GraphQL and stable capability tests still pass
- [x] Typecheck passes after extraction

---

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Raw GraphQL requester | `src/raw-graphql-client.ts` | COMPLETED | Covered by existing `src/lib.test.ts` |
| Client composition update | `src/lib.ts` | COMPLETED | Covered by existing `src/lib.test.ts` |
| Design updates | `design-docs/specs/*.md` | COMPLETED | N/A |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001 |

## Completion Criteria

- [x] Raw GraphQL escape hatch is isolated into a dedicated module
- [x] Stable/public capability routing remains behaviorally unchanged
- [x] Docs and plans describe the new boundary accurately
- [x] Typecheck and targeted tests pass

## Progress Log

### Session: 2026-03-08 23:40
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Architecture review found the repository broadly aligned with the intended three-layer model, but the raw GraphQL escape hatch still shared too much implementation space with the stable planner/executor inside `src/lib.ts`.
- Extracted raw GraphQL execution into `src/raw-graphql-client.ts` without changing the public behavior, then re-ran targeted tests and typecheck.
