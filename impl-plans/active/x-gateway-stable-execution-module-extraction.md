# X Gateway Stable Execution Module Extraction Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#module-boundaries-planned`
**Created**: 2026-03-08
**Last Updated**: 2026-04-05

---

## Design Document Reference

**Source**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/design-public-graphql-contract.md`

### Summary
The current repository behavior already matches the intended stable public-contract -> capability-planner -> internal-adapter architecture more closely than the older handoff suggested. The remaining gap is structural: `src/lib.ts` still owns the stable capability execution registry and the planner-to-adapter wiring for reviewed stable capabilities. This plan extracts that execution layer into a dedicated module so stable capability dispatch is enforced as an internal boundary.

### Scope
**Included**:
- extract the stable capability execution registry and generic execution wiring into a dedicated TypeScript module
- keep the concrete REST/GraphQL transport adapters in `src/lib.ts` for now
- preserve the current CLI, SDK, auth-readiness, and project-owned GraphQL behavior

**Excluded**:
- moving concrete transport adapter implementations out of `src/lib.ts`
- adding new capabilities or new fallback routes
- changing the external CLI or SDK contract

---

## Tasks

### TASK-001: Module Boundary Design Notes
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `design-docs/specs/architecture.md` updated with the extracted stable execution boundary
- this implementation plan recorded in `impl-plans/active/`

**Completion Criteria**:
- [x] Architecture docs describe the new execution-layer boundary explicitly
- [x] Plan captures which responsibilities still remain in `src/lib.ts`

### TASK-002: Stable Execution Module Extraction
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/stable-capability-executor.ts`
- `src/lib.ts` refactored to import and use the extracted execution helpers

**Completion Criteria**:
- [x] Stable capability registry-driven dispatch is no longer implemented directly inside `src/lib.ts`
- [x] Stable SDK helpers and `graphqlQuery(...)` still share the same executor path
- [x] Transport adapter selection remains driven by reviewed planner metadata

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
| Stable execution module | `src/stable-capability-executor.ts` | COMPLETED | Passed |
| Library integration refactor | `src/lib.ts` | COMPLETED | Passed |
| Verification | repository | COMPLETED | Passed |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-002 |

## Completion Criteria

- [x] Stable capability execution is structurally separated from the public SDK surface
- [x] Public GraphQL and direct stable helpers still dispatch through the same reviewed execution layer
- [x] Verification passes after the extraction

## Progress Log

### Session: 2026-03-08 23:59
**Tasks Completed**: TASK-001
**Tasks In Progress**: TASK-002
**Blockers**: None
**Notes**:
- Architecture review found the current repository already broadly aligned with the intended product goal: raw X web GraphQL is now isolated to the explicit escape hatch, and the stable public GraphQL-shaped contract resolves onto stable capabilities.
- The remaining design mismatch is structural rather than behavioral: `src/lib.ts` still owns stable capability execution wiring, so this iteration extracts that layer into its own module before any later adapter extraction.

### Session: 2026-03-09 00:12
**Tasks Completed**: TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Extracted the stable capability execution registry and shared planner-to-adapter dispatch into `src/stable-capability-executor.ts`.
- Kept concrete REST adapter creation in `src/lib.ts` for this slice so the external contract and reviewed routing behavior remain unchanged.
- Revalidated the extraction with `bun run typecheck`, `bun test`, and `bun run build`.

### Session: 2026-04-05 18:35 JST
**Tasks Completed**: Terminology refresh
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Updated the still-active extraction plan wording so it refers to the current `graphqlQuery(...)` SDK surface instead of the removed `apiRequest(...)` name.
