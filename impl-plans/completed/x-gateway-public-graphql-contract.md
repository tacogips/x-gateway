# X Gateway Public GraphQL Contract Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/design-public-graphql-contract.md
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- design-docs/specs/design-public-graphql-contract.md
- design-docs/specs/architecture.md
- design-docs/specs/command.md
- design-docs/specs/design-api-inventory.md

### Summary
Add the missing public-contract and planning layer by introducing a project-owned GraphQL-shaped request path that resolves onto the reviewed capability adapters already restored in the hybrid baseline.

### Scope
**Included**:
- capability-registry metadata for public operation names, read/write classification, and routing preferences
- project-owned GraphQL parser for the first supported field set
- explicit request-to-capability planner
- CLI and SDK wiring for `api request`
- tests and docs for the first public-contract slice

**Excluded**:
- full GraphQL spec compliance
- variables, fragments, aliases, or directives in the first parser slice
- `likedPosts` implementation beyond explicit planned/unsupported handling
- media, article, and broader timeline/social capability restoration

---

## Tasks

### TASK-001: Registry Metadata and Planner Boundary
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.ts` capability-registry metadata for public operation names and routing preferences
- planner types for request-to-capability resolution

**Completion Criteria**:
- [x] Registry rows expose public operation names and read/write classification
- [x] Preferred and fallback transport metadata are explicit
- [x] Planner boundary exists separately from raw GraphQL transport execution

### TASK-002: Public GraphQL Parser and Execution
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/lib.ts` project-owned GraphQL parser and planner-backed execution path
- stable response shaping for the currently implemented capability set

**Completion Criteria**:
- [x] `accountMe` and `post(id)` resolve through the planner
- [x] `createPost`, `deletePost`, `replyToPost`, `quotePost`, `repostPost`, and `unrepostPost` resolve through the planner
- [x] Unsupported planned fields fail explicitly without falling through to raw X GraphQL

### TASK-003: CLI Contract Exposure
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/cli.ts` `api request --query <graphql>` command
- reader/full mutation gating for the project-owned GraphQL surface

**Completion Criteria**:
- [x] Full CLI exposes `api request`
- [x] Reader CLI rejects public-contract mutations
- [x] Usage text distinguishes `api request` from raw `graphql request`

### TASK-004: Verification and Follow-Up Tracking
**Status**: Completed
**Parallelizable**: No (depends on TASK-002, TASK-003)
**Deliverables**:
- `src/lib.test.ts` regression coverage for parser/planner/CLI behavior
- plan/doc/progress updates for the next slice

**Completion Criteria**:
- [x] Typecheck passes
- [x] Tests pass
- [x] Build passes
- [x] Remaining backlog is explicit (`likedPosts`, broader parser coverage, further planner extraction)

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Public GraphQL contract design | `design-docs/specs/design-public-graphql-contract.md` | COMPLETED | N/A |
| Planner and parser | `src/lib.ts` | COMPLETED | Pending |
| CLI public-contract command | `src/cli.ts` | COMPLETED | Pending |
| Verification | `src/lib.test.ts` | COMPLETED | Covered |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-004 | TASK-002, TASK-003 |

## Completion Criteria

- [x] Project-owned GraphQL requests resolve onto the current stable capability set
- [x] Raw `graphql request` remains isolated as a low-level escape hatch
- [x] Capability metadata is explicit enough for future planner extraction
- [x] Tests and type checks pass for the delivered slice

## Progress Log

### Session: 2026-03-08
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- The repository already had the hybrid baseline, but it still lacked the public-contract and planner layer described in the handoff.
- This iteration adds the first project-owned GraphQL request path on top of the existing reviewed capability adapters instead of exposing raw X web GraphQL as the normal contract.
- `likedPosts` remains intentionally planned-only in this slice so the public contract can name it without falsely claiming live support.
- Verification completed with `bun test`, `bun run typecheck`, and `bun run build`.
