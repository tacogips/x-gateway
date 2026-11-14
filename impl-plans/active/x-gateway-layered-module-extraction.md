# X Gateway Layered Module Extraction Implementation Plan

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
The current behavior already follows the intended public-contract -> capability-planner -> adapter architecture, but the implementation still concentrates too much of that logic in `src/lib.ts`. This plan performs the first structural extraction pass so the separation is enforced by modules, not only by conventions inside one file.

### Scope
**Included**:
- extract capability metadata and reviewed route-planning metadata into dedicated modules
- extract the project-owned GraphQL parser into a dedicated module
- keep current CLI, SDK, and test behavior unchanged while reducing `src/lib.ts` responsibilities

**Excluded**:
- moving adapter implementations out of `src/lib.ts`
- changing stable public CLI or SDK contracts
- adding new capability families or new transport routes

---

## Tasks

### TASK-001: Extraction Design Notes
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `design-docs/specs/architecture.md` updated with the first extraction boundary
- this implementation plan recorded in `impl-plans/active/`

**Completion Criteria**:
- [x] Architecture docs describe the extracted planner/public-contract modules
- [x] Plan captures the remaining extraction scope explicitly

### TASK-002: Metadata and Parser Module Extraction
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/capability-metadata.ts`
- `src/public-graphql-parser.ts`
- `src/lib.ts` refactored to import those modules

**Completion Criteria**:
- [x] Capability registry and reviewed route registry are no longer declared in `src/lib.ts`
- [x] Public GraphQL parsing logic is no longer declared in `src/lib.ts`
- [x] External CLI/SDK behavior remains unchanged

### TASK-003: Verification
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- repository verification via typecheck, tests, and build

**Completion Criteria**:
- [x] `bun run typecheck` passes
- [x] `bun test` passes
- [x] `bun run build` passes

### TASK-004: Next Extraction Boundary
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- follow-on notes for extracting stable capability execution and adapter implementations from `src/lib.ts`

**Completion Criteria**:
- [x] Remaining responsibilities inside `src/lib.ts` are documented
- [x] A later iteration can move execution/adapters without redoing this extraction

---

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Capability metadata | `src/capability-metadata.ts` | COMPLETED | Passed |
| Public GraphQL parser | `src/public-graphql-parser.ts` | COMPLETED | Passed |
| Library refactor | `src/lib.ts` | COMPLETED | Passed |
| Follow-on extraction notes | `impl-plans/active/x-gateway-layered-module-extraction.md` | COMPLETED | N/A |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-002 |
| TASK-004 | TASK-002 |

## Completion Criteria

- [x] Registry and parser boundaries are enforced by dedicated modules
- [x] `src/lib.ts` no longer owns capability metadata or public GraphQL parsing
- [x] Verification passes after the extraction

## Progress Log

### Session: 2026-03-08 23:05
**Tasks Completed**: TASK-001
**Tasks In Progress**: TASK-002
**Blockers**: None
**Notes**:
- Review of the current repository found the behavioral architecture already aligned with the intended product direction, but the structural separation was still weak because registry and parser layers remained embedded in `src/lib.ts`.
- This extraction pass isolates planner metadata and public-contract parsing first, while leaving stable execution/adapters for a later follow-on so the change stays low risk.

### Session: 2026-03-08 23:20
**Tasks Completed**: TASK-002, TASK-003, TASK-004
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Extracted capability registry and reviewed route-planning metadata into `src/capability-metadata.ts`.
- Extracted the project-owned GraphQL parser into `src/public-graphql-parser.ts` and kept `src/lib.ts` as the integration layer.
- Revalidated the refactor with `bun run typecheck`, `bun test`, and `bun run build`.

## Related Plans

- **Previous**: `impl-plans/active/x-gateway-registry-driven-routing.md`
- **Next**: pending follow-on extraction of stable execution and adapters
- **Depends On**: `impl-plans/active/x-gateway-capability-execution-registry.md`
