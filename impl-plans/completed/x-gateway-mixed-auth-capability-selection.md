# X Gateway Mixed Auth Capability Selection Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/architecture.md#stable-contract-with-internal-adapters
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- design-docs/specs/architecture.md
- design-docs/specs/command.md
- design-docs/specs/notes.md

### Summary
Align the hybrid adapter implementation with the intended design in mixed-auth environments by selecting the reviewed auth family per capability rather than globally preferring bearer whenever a token is present.

### Scope
**Included**:
- capability-specific auth selection for stable read and posting helpers
- mixed-auth diagnostics updates
- regression coverage for bearer+OAuth1 environments

**Excluded**:
- new capability families
- bearer-backed stable posting support
- broader transport extractions beyond the current `src/lib.ts` composition

---

## Tasks

### TASK-001: Capability-Specific Auth Selection
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.ts` capability-specific adapter selection for mixed-auth environments

**Completion Criteria**:
- [x] Stable posting helpers prefer OAuth1 whenever it is configured
- [x] Stable read helpers remain available with bearer fallback
- [x] Raw GraphQL remains bearer-only

### TASK-002: Mixed-Auth Diagnostics and Documentation
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`
- `design-docs/specs/notes.md`
- `src/lib.ts` auth diagnostics

**Completion Criteria**:
- [x] Design docs state the mixed-auth selection rule explicitly
- [x] Runtime diagnostics describe available credential families accurately
- [x] No doc section overclaims bearer-backed stable posting support

### TASK-003: Regression Coverage and Validation
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.test.ts`

**Completion Criteria**:
- [x] Tests cover bearer+OAuth1 stable posting behavior
- [x] Tests cover mixed-auth diagnostics
- [x] Typecheck, tests, and build pass

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Mixed-auth adapter selection | `src/lib.ts` | COMPLETED | Covered |
| Mixed-auth docs alignment | `design-docs/specs/*.md` | COMPLETED | N/A |
| Regression coverage | `src/lib.test.ts` | COMPLETED | Covered |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001 |

## Completion Criteria

- [x] Mixed-auth environments no longer lose stable OAuth1-backed posting support
- [x] Capability-specific auth selection is documented
- [x] Validation passes for the delivered slice

## Progress Log

### Session: 2026-03-08 15:10
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Fixed a hybrid-architecture mismatch where bearer auth globally shadowed OAuth1 even for stable capabilities that are intentionally OAuth1-backed.
- Updated auth diagnostics so mixed-auth environments expose both available credential families.
- Added regression coverage for bearer+OAuth1 shells and revalidated the implementation after the adapter-selection change.
