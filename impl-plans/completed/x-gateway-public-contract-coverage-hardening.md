# X Gateway Public Contract Coverage Hardening Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/design-public-graphql-contract.md#planner-responsibilities`
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- `design-docs/specs/design-public-graphql-contract.md`
- `design-docs/specs/architecture.md`
- `impl-plans/README.md`

### Summary
The repository already implements the intended three-layer architecture in code, but one reverse-coherence gap remained in the project-owned GraphQL contract: capability metadata could advertise a stable public operation without a matching public field registration. This pass hardens that invariant and cleans the plan inventory so the superseded GraphQL-first baseline is archived instead of lingering as active work.

### Scope
**Included**:
- bidirectional coherence checks between the public GraphQL field registry and implemented stable capability metadata
- design-doc update for the stronger invariant
- implementation-plan inventory cleanup for the superseded GraphQL-first baseline

**Excluded**:
- new capability families
- parser feature expansion
- new transport adapters

---

## Tasks

### TASK-001: Bidirectional Public-Contract Guard
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/public-api-contract.ts`

**Completion Criteria**:
- [x] Public field definitions reference implemented stable capabilities only
- [x] Implemented stable capabilities with `publicOperationName` cannot exist without a matching public field registration
- [x] Contract drift fails during planner setup instead of surfacing later as a routing mismatch

### TASK-002: Design and Plan Inventory Cleanup
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `design-docs/specs/design-public-graphql-contract.md`
- `impl-plans/README.md`
- `impl-plans/PROGRESS.json`

**Completion Criteria**:
- [x] Design docs describe the bidirectional invariant explicitly
- [x] Superseded GraphQL-first plan is archived from the active-plan index
- [x] Progress index matches the updated plan inventory

### TASK-003: Verification
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- repository verification with tests, typecheck, and build

**Completion Criteria**:
- [x] `bun test` passes
- [x] `bun run typecheck` passes
- [x] `bun run build` passes

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Public contract coherence | `src/public-api-contract.ts` | COMPLETED | Covered by repository verification |
| Design update | `design-docs/specs/design-public-graphql-contract.md` | COMPLETED | N/A |
| Plan inventory cleanup | `impl-plans/README.md`, `impl-plans/PROGRESS.json` | COMPLETED | N/A |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001, TASK-002 |

## Completion Criteria

- [x] Public GraphQL contract coverage is checked in both directions
- [x] Design docs and plan inventory match the actual architecture direction
- [x] Tests, typecheck, and build pass after the hardening pass

## Progress Log

### Session: 2026-03-08 16:35
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Architecture review confirmed the current code already follows the intended stable-contract -> capability-planner -> transport-adapter model closely enough that no large redesign was needed.
- Hardened the remaining public-contract gap by making the public field registry verify both field-to-capability and capability-to-field coverage.
- Archived the superseded GraphQL-first baseline from the active plan index so the implementation backlog reflects the current direction.
