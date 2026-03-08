# X Gateway Stable Capability Coherence Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#stable-contract-with-internal-adapters`
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/notes.md`
- `design-docs/specs/design-public-graphql-contract.md`

### Summary
The repository now has separate public-contract, planner, and adapter modules, but one structural hardening gap remained: implemented stable capabilities could still drift across capability metadata, reviewed planning routes, and executor dispatch without one explicit guard. This plan closes that gap and updates the design notes to reflect the current architecture state rather than the older transition language.

### Scope
**Included**:
- stable capability coherence guard across metadata, planning, and executor dispatch
- regression coverage for the new invariant
- design and planning doc cleanup for stale transition-state wording

**Excluded**:
- new capability families
- GraphQL parser expansion
- transport-adapter behavior changes

---

## Tasks

### TASK-001: Stable Capability Coherence Guard
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/stable-capability-executor.ts`

**Completion Criteria**:
- [x] Implemented stable capability ids must have matching planning routes
- [x] Implemented stable capability ids must have matching executor entries
- [x] Executor entries must not advertise capabilities missing from reviewed metadata/planning

### TASK-002: Regression Verification
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`

**Completion Criteria**:
- [x] Tests assert the stable implemented-capability baseline remains aligned
- [x] The invariant is exercised through normal client construction

### TASK-003: Design-State Cleanup
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/notes.md`

**Completion Criteria**:
- [x] Design docs describe planner/executor coherence as an explicit contract
- [x] Stale wording about the planner/public-contract layer being the "next missing layer" is removed

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Stable capability coherence guard | `src/stable-capability-executor.ts` | COMPLETED | Covered by `src/lib.test.ts` |
| Regression verification | `src/lib.test.ts` | COMPLETED | Passed |
| Design cleanup | `design-docs/specs/*.md` | COMPLETED | N/A |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001 |

## Completion Criteria

- [x] Implemented stable capabilities cannot silently drift across metadata, planning, and executor layers
- [x] Tests cover the baseline capability set
- [x] Design docs reflect the current architecture instead of the previous transition state

## Progress Log

### Session: 2026-03-08 23:59
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Architecture review found the intended three-layer behavior already present, so this slice hardens the remaining internal contract boundary instead of reopening the design.
- Added an executor-level coherence guard so implemented stable capabilities must stay aligned across metadata, planning, and dispatch.
- Cleaned up stale design notes that still described the planner/public-contract layer as future work even though it is already implemented.
