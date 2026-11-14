# X Gateway GraphQL-Only Command Surface Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#capability-matrix-implementation-target`, `design-docs/specs/command.md#public-command-shape`
**Created**: 2026-04-05
**Last Updated**: 2026-04-05

---

## Summary

Remove legacy non-GraphQL convenience commands from the public surface so `api request` remains the canonical reviewed interface for the project-owned GraphQL contract.

## Scope

**Included**:
- removal of public CLI command groups for legacy convenience surfaces
- usage/help text updates
- regression coverage for removed command behavior

**Excluded**:
- internal capability executor removal
- capability metadata removal
- canonical public GraphQL field removal

## Tasks

### TASK-001: Remove Legacy Command Groups
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/cli.ts`
- `src/lib.test.ts`

**Completion Criteria**:
- [x] legacy `account`, `usage`, `post`, and `timeline` command groups are no longer supported
- [x] CLI remediation points callers to `api request`
- [x] usage text no longer advertises legacy convenience groups

### TASK-002: Verification
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`

**Completion Criteria**:
- [x] `bun test` passes
- [x] `bun run typecheck` passes
- [x] `bun run build` passes

## Progress Log

### Session: 2026-04-05 15:35 JST
**Tasks Completed**: None yet
**Tasks In Progress**: TASK-001
**Blockers**: None
**Notes**:
- User clarified that the intended public interface is GraphQL-only, so earlier transitional command-surface assumptions are no longer valid.

### Session: 2026-04-05 16:05 JST
**Tasks Completed**: TASK-001, TASK-002
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Removed legacy convenience commands and the raw-upstream GraphQL requester from the public surface.
- Narrowed the public SDK to the project-owned GraphQL request contract and diagnostics helpers.
- Verified the final state with `bun run typecheck`, `bun test`, and `bun run build`.
