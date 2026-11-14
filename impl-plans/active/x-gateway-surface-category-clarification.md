# X Gateway Surface Category Clarification Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#stable-contract-with-internal-adapters`
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`
- `design-docs/specs/design-public-graphql-contract.md`

### Summary
The current repository already implements the intended three-layer split, but one inventory-level ambiguity remained: `graphql.request` still appeared alongside stable capability entries without an explicit surface classification. This plan clarifies registry semantics so stable contract operations, deferred capabilities, and the raw GraphQL escape hatch are visibly distinct.

### Scope
**Included**:
- capability-registry metadata for stable contract vs escape hatch vs deferred surfaces
- regression coverage for capability inventory output
- design-doc updates describing the explicit surface distinction

**Excluded**:
- transport-planner behavior changes
- new capabilities or new adapter routes
- CLI output format redesign beyond the registry metadata

---

## Tasks

### TASK-001: Add Surface Category Metadata
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/capability-metadata.ts`
- `src/lib.ts`

**Completion Criteria**:
- [x] Capability descriptors distinguish stable contract entries from the raw GraphQL escape hatch
- [x] Deferred capabilities remain visibly distinct from implemented stable capabilities
- [x] Surface metadata is exported through the public SDK types

### TASK-002: Regression Coverage
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`

**Completion Criteria**:
- [x] Capability inventory tests assert stable capabilities, escape hatch entries, and deferred capabilities carry distinct surface categories
- [x] Existing stable-capability alignment tests continue to pass

### TASK-003: Design Clarification
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`
- `design-docs/specs/design-public-graphql-contract.md`

**Completion Criteria**:
- [x] Design docs state that inventory metadata must not present raw GraphQL as a peer stable contract
- [x] Public-contract docs explicitly keep raw GraphQL outside the stable contract category

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Surface category metadata | `src/capability-metadata.ts` | COMPLETED | Covered by `src/lib.test.ts` |
| SDK export update | `src/lib.ts` | COMPLETED | Covered by `src/lib.test.ts` |
| Inventory regression coverage | `src/lib.test.ts` | COMPLETED | Passed |
| Design clarification | `design-docs/specs/*.md` | COMPLETED | N/A |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001 |

## Completion Criteria

- [x] Registry metadata explicitly distinguishes stable contract, escape-hatch, and deferred surfaces
- [x] Tests cover the new distinction in capability inventory output
- [x] Design docs describe the distinction clearly

## Progress Log

### Session: 2026-03-08 23:20
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Architecture review found the repository already aligned with the intended public-contract, capability-planner, and upstream-adapter split for the current baseline.
- Added explicit surface-category metadata so `graphql.request` is marked as an escape hatch instead of appearing as a peer stable contract in capability inventory output.

