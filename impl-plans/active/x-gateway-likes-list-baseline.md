# X Gateway Likes List Baseline Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#capability-matrix-implementation-target`
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`
- `design-docs/specs/design-public-graphql-contract.md`
- `design-docs/specs/design-api-inventory.md`

### Summary
Restore `likes.list` as a reviewed stable read capability so callers can fetch liked posts through the stable CLI, SDK, and project-owned GraphQL contract without depending on raw X web GraphQL details.

### Scope
**Included**:
- capability-registry update for `likes.list`
- planner-backed SDK method and CLI command for liked-post reads
- project-owned GraphQL `likedPosts(...)` execution path
- auth-readiness and regression coverage for the new capability

**Excluded**:
- like/unlike mutations
- bookmarks, timelines, or social-graph capability families
- GraphQL fallback transport for likes
- extraction of planner/public-contract code into dedicated modules

---

## Tasks

### TASK-001: Stable Likes Capability Contract
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.ts` types and registry metadata for `likes.list`
- design docs updated to advertise `likes.list` as a stable capability

**Completion Criteria**:
- [x] Capability registry metadata reflects the reviewed `likes.list` auth and transport path
- [x] Stable command and public GraphQL docs both reference the same capability

### TASK-002: Planner and Adapter Implementation
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/lib.ts` read adapter and planner execution for `likes.list`
- `src/cli.ts` `likes list` command path

**Completion Criteria**:
- [x] SDK exposes a stable `likesList` method
- [x] `api request` executes `likedPosts(...)` through the capability planner
- [x] CLI exposes `likes list --user-id <id> [--limit <count>]`

### TASK-003: Verification
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts` regression coverage for SDK, CLI, GraphQL contract, and auth readiness

**Completion Criteria**:
- [x] Tests cover OAuth1 and bearer read paths for `likes.list`
- [x] Reader CLI accepts `likes list`
- [x] `bun run typecheck`, `bun run test`, and `bun run build` pass

---

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Likes capability contract | `src/lib.ts` | COMPLETED | Pending |
| Likes planner and CLI path | `src/lib.ts`, `src/cli.ts` | COMPLETED | Passed |
| Regression coverage | `src/lib.test.ts` | COMPLETED | Passed |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001, TASK-002 |

## Completion Criteria

- [x] Stable `likes.list` contract is documented
- [x] Stable CLI, SDK, and project-owned GraphQL surfaces all route through the same reviewed capability
- [x] Verification passes for the restored likes baseline

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
- Added a reviewed `likes.list` adapter path for both OAuth1 and bearer read flows and exposed it through the SDK, CLI, and project-owned GraphQL contract.
- Revalidated the restored baseline with `bun run typecheck`, `bun run test`, and `bun run build`.
