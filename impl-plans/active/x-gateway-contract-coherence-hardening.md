# X Gateway Contract Coherence Hardening Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#stable-contract-with-internal-adapters`
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/design-public-graphql-contract.md`
- `design-docs/specs/notes.md`

### Summary
The current repository already follows the intended three-layer model in broad strokes, but two hardening gaps remain: the project-owned GraphQL field registry can still drift from capability metadata, and runtime diagnostics do not identify the exact reviewed auth/transport route that executed. This plan closes those gaps without changing the public CLI or SDK contract.

### Scope
**Included**:
- public GraphQL field registry coherence checks against capability metadata
- planner diagnostic labeling that names both transport and auth family
- regression coverage for the hardened invariants

**Excluded**:
- new capability families
- GraphQL parser feature expansion
- moving raw GraphQL transport out of `src/lib.ts`

---

## Tasks

### TASK-001: Registry Coherence Guard
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/public-api-contract.ts` coherence checks between public field definitions and stable capability metadata

**Completion Criteria**:
- [x] Duplicate public field names are rejected internally
- [x] Every project-owned GraphQL field references an existing stable capability
- [x] `publicOperationName` stays aligned with the public field registry

### TASK-002: Planner Diagnostic Hardening
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/capability-runtime.ts` route labels that include both transport family and auth family
- design docs updated to record the diagnostic rule

**Completion Criteria**:
- [x] Runtime diagnostics distinguish `rest-v1/oauth1`, `rest-v2/bearer`, and `graphql-web/bearer`
- [x] Design docs describe route labeling as part of the planner contract

### TASK-003: Regression Verification
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts` regression assertions for route labeling and public-contract metadata alignment
- repository verification via tests, typecheck, and build

**Completion Criteria**:
- [x] Tests cover the new diagnostic label format
- [x] Tests guard the public-operation metadata baseline
- [x] `bun test`, `bun run typecheck`, and `bun run build` pass

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Public contract coherence | `src/public-api-contract.ts` | COMPLETED | Covered |
| Planner diagnostics | `src/capability-runtime.ts` | COMPLETED | Covered |
| Regression verification | `src/lib.test.ts` | COMPLETED | Passed |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-003 | TASK-001, TASK-002 |

## Completion Criteria

- [x] Public GraphQL field definitions cannot silently drift from capability metadata
- [x] Mixed-auth/runtime failures identify the reviewed route that actually ran
- [x] Tests, typecheck, and build pass after the hardening pass

## Progress Log

### Session: 2026-03-08 12:55
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Architecture review found the repository broadly aligned with the intended three-layer design, so this pass focused on hardening rather than a large rewrite.
- Added a coherence guard so the project-owned GraphQL contract cannot drift silently from stable capability metadata.
- Tightened planner diagnostics to report the actual reviewed route label and re-ran tests, typecheck, and build.
