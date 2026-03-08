# X Gateway Capability Runtime Extraction Implementation Plan

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
The repository now behaves like the intended public-contract -> capability-planner -> adapter architecture, but the runtime boundary is still too soft because route selection, readiness derivation, and planner-to-adapter execution are embedded in `src/lib.ts`. This plan extracts that runtime into a dedicated module so the internal layering is reflected in code structure.

### Scope
**Included**:
- extract capability runtime planning helpers into a dedicated TypeScript module
- move auth-readiness derivation into that same runtime layer
- keep stable CLI, SDK, and project-owned GraphQL behavior unchanged

**Excluded**:
- moving REST/GraphQL transport adapters out of `src/lib.ts`
- adding new capabilities or new transport fallbacks
- changing the external CLI or SDK contract

---

## Tasks

### TASK-001: Runtime Extraction Design Notes
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `design-docs/specs/architecture.md` updated with the new runtime boundary
- this implementation plan recorded in `impl-plans/active/`

**Completion Criteria**:
- [x] Architecture docs name the runtime extraction boundary explicitly
- [x] Plan captures which responsibilities remain in `src/lib.ts`

### TASK-002: Capability Runtime Module Extraction
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/capability-runtime.ts`
- `src/lib.ts` refactored to import and use the extracted runtime helpers

**Completion Criteria**:
- [x] Route selection is no longer implemented directly inside `src/lib.ts`
- [x] Auth-readiness derivation is no longer implemented directly inside `src/lib.ts`
- [x] Stable capability execution still dispatches through the reviewed route registry

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
| Capability runtime helpers | `src/capability-runtime.ts` | COMPLETED | Passed |
| Library integration refactor | `src/lib.ts` | COMPLETED | Passed |
| Verification | repository | COMPLETED | Passed |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-002 |

## Completion Criteria

- [x] Capability planning/runtime helpers are structurally separated from the public SDK surface
- [x] Auth readiness and route selection still derive from the reviewed route registry
- [x] Verification passes after the extraction

## Progress Log

### Session: 2026-03-08 23:45
**Tasks Completed**: TASK-001
**Tasks In Progress**: TASK-002
**Blockers**: None
**Notes**:
- Review of the current working tree found the behavior already broadly aligned with the intended three-layer architecture.
- The main remaining architectural gap is structural: `src/lib.ts` still owns too much runtime planning and readiness logic.

### Session: 2026-03-09 00:10
**Tasks Completed**: TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Extracted reviewed route selection, auth-readiness derivation, and planner-to-adapter execution wiring into `src/capability-runtime.ts`.
- Kept transport adapters in `src/lib.ts` for this iteration, and preserved auth-specific adapter diagnostics after the extraction changed an error-detail expectation.
- Revalidated the refactor with `bun run typecheck`, `bun test`, and `bun run build`.
