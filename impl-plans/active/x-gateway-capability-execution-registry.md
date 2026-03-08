# X Gateway Capability Execution Registry Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#stable-contract-with-internal-adapters`
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/design-public-graphql-contract.md`

### Summary
The repository already has a project-owned public GraphQL field registry and a reviewed route-planning registry, but stable capability execution is still duplicated between direct SDK helpers and `apiRequest`. This plan introduces one internal execution registry so capability selection remains the single source of truth after planning.

### Scope
**Included**:
- one shared stable-capability execution registry in `src/lib.ts`
- refactor of stable SDK helpers and `apiRequest` to dispatch through that registry
- regression verification for the refactor

**Excluded**:
- extracting registries into separate directories
- adding new capability families
- changing the external CLI or SDK contract

---

## Tasks

### TASK-001: Execution Registry Definition
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.ts` typed stable-capability execution registry keyed by capability id

**Completion Criteria**:
- [x] Stable capability ids are centralized in one execution registry
- [x] Registry entries include the capability label and adapter-dispatch callback

### TASK-002: Shared Dispatch Refactor
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/lib.ts` shared executor used by direct SDK helpers and `apiRequest`

**Completion Criteria**:
- [x] `apiRequest` no longer needs a per-capability execution switch
- [x] Stable SDK helpers dispatch through the same executor path
- [x] Public GraphQL execution remains isolated from raw GraphQL passthrough

### TASK-003: Verification
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- repository verification via typecheck, tests, and build

**Completion Criteria**:
- [x] `bun run typecheck` passes
- [x] `bun test` passes
- [x] `bun run build` passes

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Execution registry | `src/lib.ts` | COMPLETED | Covered |
| Shared capability dispatch | `src/lib.ts` | COMPLETED | Covered |
| Verification | repository | COMPLETED | Passed |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001, TASK-002 |

## Completion Criteria

- [x] Stable capability execution is registry-driven instead of duplicated by entrypoint
- [x] Direct SDK helpers and public GraphQL use the same reviewed capability dispatcher
- [x] Typecheck, tests, and build pass after the refactor

## Progress Log

### Session: 2026-03-08 22:35
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Architecture review found the product surface already broadly aligned with the intended three-layer model, but capability execution was still duplicated after planning.
- Added a shared execution registry so the public GraphQL contract and direct stable helpers resolve through the same internal capability dispatcher.
- Re-ran `bun run typecheck`, `bun test`, and `bun run build` after the refactor.
