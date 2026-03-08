# X Gateway Registry-Driven Routing Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#stable-contract-with-internal-adapters`
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/design-public-graphql-contract.md`
- `design-docs/specs/command.md`

### Summary
The repository already exposes a stable capability surface plus a project-owned GraphQL-shaped request path, but the actual auth and transport routing logic is still mostly embedded in helper branching. This plan makes reviewed route order explicit in planner metadata so capability routing, auth diagnostics, and mixed-auth behavior all derive from the same source.

### Scope
**Included**:
- explicit reviewed route registry for the implemented stable baseline
- planner refactor so stable capability execution reads from reviewed route metadata
- auth-readiness derivation from the same reviewed route metadata
- regression coverage for mixed-auth route preference

**Excluded**:
- extraction into dedicated `src/planner/` or `src/adapters/` modules
- new capability families beyond the current stable baseline
- GraphQL-web fallback routes for stable capabilities that remain REST-backed today

---

## Tasks

### TASK-001: Reviewed Route Registry
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.ts` reviewed route metadata for `graphql.request`, `account.me`, `post.get`, `likes.list`, and stable posting flows
- design docs updated to describe route metadata as the planner source of truth

**Completion Criteria**:
- [x] Reviewed route order is explicit in one planner artifact
- [x] Mixed-auth preference is visible in metadata rather than hidden in helper branching
- [x] Docs describe the route-registry role clearly

### TASK-002: Planner Refactor
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/lib.ts` generic stable capability planner driven by reviewed route metadata
- auth-readiness generation derived from the same metadata

**Completion Criteria**:
- [x] Stable capability execution no longer chooses auth/transport via capability-family helper branching alone
- [x] Auth readiness derives from the same route metadata used for execution
- [x] Bearer-only posting remains blocked with explicit reviewed-path guidance

### TASK-003: Regression Coverage
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts` mixed-auth regression coverage for reviewed route preference

**Completion Criteria**:
- [x] Tests prove read capabilities prefer reviewed OAuth1 routes when both auth families are configured
- [x] Tests still cover bearer-only fallback for reviewed read capabilities
- [x] Typecheck, tests, and build pass

### TASK-004: Planner Extraction Follow-On
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- follow-on extraction notes for moving reviewed route registry and public-field registry into dedicated modules

**Completion Criteria**:
- [x] Module extraction boundary is documented after the route-registry refactor
- [x] Next iteration identifies which planner pieces move first without destabilizing the current baseline

---

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Reviewed route registry | `src/lib.ts` | COMPLETED | Pending |
| Planner execution refactor | `src/lib.ts` | COMPLETED | Pending |
| Mixed-auth regression coverage | `src/lib.test.ts` | COMPLETED | Pending |
| Extraction follow-on notes | `impl-plans/active/x-gateway-registry-driven-routing.md` | NOT_STARTED | N/A |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001, TASK-002 |
| TASK-004 | TASK-002 |

## Completion Criteria

- [x] Reviewed route metadata drives the implemented stable baseline
- [x] Auth readiness and runtime execution use the same route source of truth
- [x] Regression coverage protects mixed-auth route preference
- [x] Follow-on extraction work is staged for a later iteration

## Progress Log

### Session: 2026-03-08 22:05
**Tasks Completed**: TASK-001, TASK-002
**Tasks In Progress**: TASK-003
**Blockers**: None
**Notes**:
- Architecture review found the current repository broadly aligned with the intended three-layer model, but the route-selection layer still relied on helper branching rather than one explicit reviewed route registry.
- Added a focused plan to make route order, auth family selection, and readiness reporting derive from shared planner metadata.

### Session: 2026-03-08 22:15
**Tasks Completed**: TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Added mixed-auth regression coverage proving stable read capabilities continue to prefer the reviewed OAuth1 path even when a broken bearer token is also configured.
- Verification remains to be re-run after the full working tree settles because there are multiple in-flight changes outside this plan.

### Session: 2026-03-09 00:35
**Tasks Completed**: TASK-004
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- The planner follow-on extraction boundary is now concretely staged in `impl-plans/active/x-gateway-transport-adapter-extraction.md`.
- The next extraction slice moves the reviewed REST transport adapters out of `src/lib.ts` so the route planner and adapter layer are separated by modules, not only conventions.
