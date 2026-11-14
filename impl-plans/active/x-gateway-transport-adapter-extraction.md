# X Gateway Transport Adapter Extraction Implementation Plan

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
The repository already separates the public request contract, capability planner, and stable capability executor into dedicated modules. The remaining structural leak is that the concrete REST transport adapters still live inside `src/lib.ts`, which keeps upstream transport concerns mixed with the public SDK integration layer. This plan extracts those reviewed adapters into a dedicated module and tightens the stable-posting adapter factory so planner-selected auth remains explicit.

### Scope
**Included**:
- extract reviewed REST capability adapters into a dedicated TypeScript module
- move REST payload mapping helpers and post/likes response shaping into that module
- make stable-posting adapter factory selection explicitly auth-aware

**Excluded**:
- moving raw GraphQL request transport out of `src/lib.ts`
- adding new capability families or new fallback routes
- changing the external CLI or SDK contract

---

## Tasks

### TASK-001: Extraction Design Notes
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `design-docs/specs/architecture.md`
- this implementation plan recorded in `impl-plans/active/`

**Completion Criteria**:
- [x] Architecture docs name the dedicated transport-adapter module explicitly
- [x] Plan captures the remaining in-`src/lib.ts` transport scope accurately

### TASK-002: Transport Adapter Module Extraction
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/capability-adapters.ts`
- `src/lib.ts`
- `src/stable-capability-executor.ts`

**Completion Criteria**:
- [x] Reviewed REST adapters are no longer implemented directly inside `src/lib.ts`
- [x] Stable-posting adapter creation receives the planner-selected auth mode explicitly
- [x] Stable capability execution behavior remains unchanged

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
| Transport adapters | `src/capability-adapters.ts` | COMPLETED | Passed |
| Library integration | `src/lib.ts` | COMPLETED | Passed |
| Stable executor boundary | `src/stable-capability-executor.ts` | COMPLETED | Passed |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-002 |

## Completion Criteria

- [x] Transport-specific REST adapter code is structurally separated from the public SDK integration layer
- [x] Planner-selected auth stays explicit at the adapter-factory boundary
- [x] Verification passes after the extraction

## Progress Log

### Session: 2026-03-09 00:35
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Review of the current working tree found the behavior already aligned with the intended three-layer product direction, but the adapter layer was still structurally mixed into `src/lib.ts`.
- Extracted reviewed REST capability adapters and payload-mapping helpers into `src/capability-adapters.ts`.
- Tightened the stable-posting adapter factory so planner-selected auth remains an explicit part of the internal contract.
