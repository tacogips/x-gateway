# X Gateway Likes List Baseline Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#capability-matrix-implementation-target`
**Created**: 2026-03-08
**Last Updated**: 2026-04-05

---

## Design Document Reference

**Source**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`
- `design-docs/specs/design-public-graphql-contract.md`
- `design-docs/specs/design-api-inventory.md`

### Summary
This plan is complete for the current repository baseline: `likes.list` was removed from the reviewed stable surface, explicit guardrails were added, and regression coverage now keeps that deferred state truthful. Any future restoration of `likes.list` should happen in a new implementation plan after a reviewed live adapter route is verified.

### Scope
**Included**:
- capability-registry truthfulness corrections for `likes.list`
- removal of `likes` from the canonical CLI and project-owned GraphQL contract while the live route remains unverified
- compatibility-safe SDK rejection behavior and regression coverage

**Excluded**:
- like/unlike mutations
- bookmarks, timelines, or social-graph capability families
- new liked-post transport implementation in the same rollback slice
- extraction of planner/public-contract code into dedicated modules

---

## Tasks

### TASK-001: Capability Truthfulness Rollback
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.ts` types and registry metadata for `likes.list`
- design docs updated to stop advertising `likes.list` as a stable capability

**Completion Criteria**:
- [x] Capability registry metadata no longer advertises `likes.list` as a stable reviewed capability
- [x] Stable command and public GraphQL docs both remove `likes` from the canonical surface

### TASK-002: Public Surface Guardrails
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/lib.ts` SDK rejection path for `likes.list`
- `src/cli.ts` command and `api request` rejection behavior for deferred likes usage

**Completion Criteria**:
- [x] SDK rejects stable `likesList` usage with explicit deferral guidance
- [x] `api request` rejects `likes(...)` as outside the stable contract
- [x] CLI rejects `likes list` as a deferred surface

### TASK-003: Verification
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts` regression coverage for SDK, CLI, GraphQL contract, and auth readiness

**Completion Criteria**:
- [x] Tests cover explicit deferral of `likes.list` across SDK, CLI, metadata, and public GraphQL
- [x] Reader and full CLI both reject `likes list`
- [x] `bun run typecheck`, `bun run test`, and `bun run build` pass

---

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Likes capability contract | `src/lib.ts` | COMPLETED | Covered |
| Likes public-surface guardrails | `src/lib.ts`, `src/cli.ts`, `src/public-api-contract.ts` | COMPLETED | Covered |
| Regression coverage | `src/lib.test.ts` | COMPLETED | Covered |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001, TASK-002 |

## Completion Criteria

- [x] `likes.list` is no longer falsely advertised as a stable reviewed capability
- [x] Stable CLI, SDK, and project-owned GraphQL surfaces reject `likes` consistently while the route is unverified
- [x] Verification passes for the rollback/deferral baseline

## Progress Log

### Session: 2026-03-08 21:10
**Tasks Completed**: TASK-001
**Tasks In Progress**: TASK-002
**Blockers**: None
**Notes**:
- The repository already matches the intended three-layer model for the current account/post baseline, so this slice focuses on the missing stable `likes.list` capability rather than redesigning the public contract again.
- `likes.list` will be restored as a REST-backed read capability with explicit planner routing and without leaking raw upstream GraphQL details into the stable surface.

### Session: 2026-03-08 21:20
**Tasks Completed**: TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Earlier iteration note superseded by later review: the attempted `likes.list` restoration was not retained because live CLI verification showed the route was not defensible.
- Verification for the current branch baseline is captured in the later rollback session entries instead.

### Session: 2026-03-08 23:05 JST
**Tasks Completed**: Plan/log truthfulness review
**Tasks In Progress**: None
**Blockers**: A reviewed live liked-post adapter route is still missing
**Notes**:
- Continued diff review confirmed the three-layer architecture still matches the intended product direction: `api request` is canonical, stable capability routing remains the internal abstraction, and raw `graphql request` remains an escape hatch only.
- Follow-up truthfulness cleanup removed the last stale implication that standalone media upload or restored `likes.list` behavior was part of the reviewed public baseline.

### Session: 2026-03-08 22:35 JST
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: A reviewed live liked-post adapter route is still missing
**Notes**:
- Continued architecture review found the documented/stable `likes` route was not actually defensible because real CLI usage currently fails with upstream HTTP 400.
- This rollback makes the public contract truthful again: `likes.list` is deferred, `likes` is removed from the canonical project-owned GraphQL contract, `likes list` is removed from the stable CLI surface, and SDK usage now fails with explicit remediation instead of silently preserving a known-broken stable claim.

### Session: 2026-04-05 19:48 JST
**Tasks Completed**: Plan closure and tracker cleanup
**Tasks In Progress**: None
**Blockers**: None for this rollback/deferral slice
**Notes**:
- Reclassified this plan from blocked to completed because the actual deliverable scope for the current baseline was the rollback and guardrail work, and all completion criteria were already satisfied.
- Future work to restore `likes.list` remains intentionally out of scope here and should be tracked by a new plan only after a reviewed live route exists.
