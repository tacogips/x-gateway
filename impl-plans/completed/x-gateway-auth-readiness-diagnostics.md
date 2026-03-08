# X Gateway Auth Readiness Diagnostics Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/command.md#auth-and-session
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- design-docs/specs/command.md
- design-docs/specs/architecture.md
- design-docs/specs/notes.md

### Summary
Improve `auth verify` so it reports capability-level readiness for the stable hybrid contract. Callers should be able to tell which reviewed commands are ready with the currently resolved credentials instead of inferring that from a generic auth-mode string.

### Scope
**Included**:
- capability-readiness diagnostics for the current stable baseline
- SDK/runtime response shape updates for `authVerify`
- CLI and design-doc alignment
- regression coverage for unconfigured, OAuth1-only, bearer-only, and mixed-auth shells

**Excluded**:
- live upstream scope introspection
- new capability families beyond the current stable baseline
- media/article/timeline restoration work

---

## Tasks

### TASK-001: Capability Readiness Response Shape
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.ts` typed readiness summary for `authVerify`

**Completion Criteria**:
- [x] `authVerify` returns capability-level readiness metadata
- [x] Readiness reasons distinguish ready, requires user-context bearer, requires OAuth1, and missing auth
- [x] Mixed-auth output shows that stable posting remains OAuth1-backed while raw GraphQL remains bearer-backed

### TASK-002: Command and Design Alignment
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `design-docs/specs/command.md`
- `design-docs/specs/notes.md`
- `impl-plans/README.md`
- `impl-plans/PROGRESS.json`

**Completion Criteria**:
- [x] `auth verify` contract documents capability readiness output
- [x] Active-plan tracking reflects this next iteration
- [x] Historical superseded plan remains clearly separated from active execution work

### TASK-003: Regression Coverage and Validation
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.test.ts`

**Completion Criteria**:
- [x] Tests cover readiness output for unconfigured, OAuth1-only, bearer-only, and mixed-auth environments
- [x] Typecheck passes
- [x] Test suite passes
- [x] Build passes

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Auth readiness payload | `src/lib.ts` | COMPLETED | Covered |
| Command/design alignment | `design-docs/specs/*.md` | COMPLETED | N/A |
| Regression coverage | `src/lib.test.ts` | COMPLETED | Covered |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001 |

## Completion Criteria

- [x] `auth verify` reports capability readiness for the stable hybrid baseline
- [x] AI callers can tell which reviewed commands are ready without reading prose-only diagnostics
- [x] Typecheck, tests, and build pass after the response-shape change

## Progress Log

### Session: 2026-03-08 18:20
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Follow-up architecture review found that the hybrid model is now correct, but `auth verify` still under-explains practical capability readiness for AI callers.
- This iteration focuses on making auth diagnostics capability-oriented so the runtime contract better matches the intent-level product surface.
- Implemented typed capability readiness rows for the stable baseline and made bearer-only `account.me` readiness explicit as conditional on a user-context bearer token.
- Updated design docs and implementation tracking, then revalidated `bun run typecheck`, `bun test`, and `bun run build`.

## Related Plans

- **Previous**: `completed/x-gateway-adapter-contract-hardening.md`
- **Next**: Future capability-restoration plans for media/article/timeline families
- **Depends On**: `completed/x-gateway-hybrid-capability-adapters.md`, `completed/x-gateway-mixed-auth-capability-selection.md`
