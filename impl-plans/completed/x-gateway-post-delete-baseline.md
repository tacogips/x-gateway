# X Gateway Post Delete Baseline Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/architecture.md#stable-contract-with-internal-adapters
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- design-docs/specs/architecture.md
- design-docs/specs/command.md
- design-docs/specs/design-api-inventory.md
- design-docs/specs/notes.md

### Summary
Extend the restored hybrid baseline with a reviewed `post delete` capability so the stable CLI/SDK contract covers the core post lifecycle without forcing callers back to raw GraphQL.

### Scope
**Included**:
- OAuth1-backed `post delete` SDK helper and CLI command
- capability registry and command/design documentation updates
- regression coverage for full CLI, reader rejection, and bearer-only rejection
- implementation-plan archive cleanup so completed plans no longer remain under `active/`

**Excluded**:
- bearer-backed stable deletion support
- media deletion or broader post lifecycle expansion
- larger module extraction beyond the current `src/lib.ts` composition

---

## Tasks

### TASK-001: Stable Delete Adapter
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.ts` OAuth1-backed `postDelete` helper wired through the stable posting adapter

**Completion Criteria**:
- [x] `post.delete` is represented in the capability registry
- [x] SDK exposes a stable `postDelete` helper
- [x] Bearer-only environments continue to reject stable delete operations

### TASK-002: CLI and Docs Alignment
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/cli.ts`
- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`
- `design-docs/specs/design-api-inventory.md`
- `design-docs/specs/notes.md`

**Completion Criteria**:
- [x] `x-gateway post delete --post-id <postId>` is exposed on the full CLI only
- [x] Reader mode continues to reject delete as a write operation
- [x] Design docs describe delete as part of the current stable baseline

### TASK-003: Regression Coverage and Plan Hygiene
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`
- `impl-plans/README.md`
- `impl-plans/PROGRESS.json`

**Completion Criteria**:
- [x] Tests cover SDK and CLI delete flows plus bearer/reader rejection
- [x] Completed implementation plans are archived under `impl-plans/completed/`
- [x] README and `PROGRESS.json` reflect the archived/completed state accurately

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Stable delete adapter | `src/lib.ts` | COMPLETED | Covered |
| CLI surface alignment | `src/cli.ts` | COMPLETED | Covered |
| Design and inventory updates | `design-docs/specs/*.md` | COMPLETED | N/A |
| Plan archive hygiene | `impl-plans/*` | COMPLETED | N/A |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001 |

## Completion Criteria

- [x] Stable delete capability is available on the full CLI/SDK surface
- [x] Bearer-only and reader-surface restrictions remain enforced
- [x] Design and implementation-plan artifacts match the delivered repository state

## Progress Log

### Session: 2026-03-08 17:10
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Added `post.delete` as the next reviewed OAuth1-backed stable posting capability through the existing REST adapter path.
- Updated CLI usage, capability docs, and inventory notes so the stable baseline covers the core create/delete/read/reply/quote/repost flows without overstating bearer support.
- Archived previously completed plans out of `impl-plans/active/` so plan state once again matches the documented workflow.
