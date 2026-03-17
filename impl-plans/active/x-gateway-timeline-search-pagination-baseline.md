# X Gateway Timeline Search Pagination Baseline Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#capability-matrix-implementation-target`
**Created**: 2026-03-17
**Last Updated**: 2026-03-17

---

## Design Document Reference

**Source**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`
- `design-docs/specs/design-api-inventory.md`
- `design-docs/specs/design-public-graphql-contract.md`

### Summary
Restore a reviewed stable read baseline for recent search and timeline-style pagination. The repository currently advertises `timeline.search` as deferred and rejects the `timeline` CLI group entirely, so there is no stable, typed contract for search results or pagination tokens despite those surfaces being called out in older plan history.

### Scope
**Included**:
- stable SDK result/input types for paginated post reads
- reviewed read-capability adapters for recent search, home timeline, user timeline, and mentions timeline
- capability metadata and planning routes aligned with the implemented baseline
- CLI support for `timeline search`, `timeline home`, `timeline user`, and `timeline mentions`
- project-owned public GraphQL fields for the same paginated read baseline
- regression coverage for pagination token plumbing, auth selection, and contract validation

**Excluded**:
- bookmarks, likes, social-graph, or DM restoration
- write-path timeline mutations
- automatic multi-page iteration helpers beyond explicit pagination tokens
- GraphQL-web persisted-query timeline mappings

---

## Tasks

### TASK-001: Stable Paginated Read Contract
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.ts`
- `src/capability-metadata.ts`
- `src/stable-capability-executor.ts`

**Completion Criteria**:
- [x] Stable capability ids include reviewed timeline/search read capabilities
- [x] Shared paginated post result and input types are exported from the SDK
- [x] Capability metadata and planning routes describe the implemented auth/transport behavior truthfully

### TASK-002: Adapter, CLI, and Public Contract Wiring
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/capability-adapters.ts`
- `src/cli.ts`
- `src/public-graphql-schema.ts`
- `src/public-api-contract.ts`

**Completion Criteria**:
- [x] Read adapters execute recent search and timeline endpoints with explicit pagination token mapping
- [x] CLI exposes reviewed timeline commands with validated flags
- [x] Public GraphQL schema and planner support paginated read fields

### TASK-003: Verification
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`

**Completion Criteria**:
- [x] Tests cover SDK, CLI, and GraphQL pagination behavior
- [x] Tests confirm capability inventory and auth-readiness alignment for new capabilities
- [x] `bun run typecheck`, `bun run test`, and `bun run build` pass

---

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Stable paginated capability contract | `src/lib.ts`, `src/capability-metadata.ts`, `src/stable-capability-executor.ts` | COMPLETED | Covered |
| Timeline/search adapters and public surfaces | `src/capability-adapters.ts`, `src/cli.ts`, `src/public-graphql-schema.ts`, `src/public-api-contract.ts` | COMPLETED | Covered |
| Regression coverage | `src/lib.test.ts` | COMPLETED | Covered |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001, TASK-002 |

## Completion Criteria

- [x] Search and timeline pagination are available through reviewed stable SDK and CLI paths
- [x] Capability metadata, planner routes, and public GraphQL contract stay coherent with the implemented baseline
- [x] Verification passes for typecheck, tests, and build

## Progress Log

### Session: 2026-03-17 18:20 JST
**Tasks Completed**: Review baseline and identify gaps
**Tasks In Progress**: TASK-001, TASK-002, TASK-003
**Blockers**: None
**Notes**:
- Review confirmed the current repository state does not implement a stable search or timeline pagination contract. `timeline.search` is explicitly deferred in metadata, the `timeline` CLI group is rejected, and there is no shared pagination abstraction in the SDK.
- The implementation baseline for this slice is explicit page-by-page pagination with stable `nextToken` and `previousToken` metadata rather than implicit auto-pagination.

### Session: 2026-03-17 19:05 JST
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Added stable read capability ids for recent search, home timeline, user timeline, and mentions timeline, with reviewed REST v2 auth-routing metadata.
- Implemented explicit page-based pagination contracts in the SDK, CLI, and project-owned GraphQL schema using normalized `pageInfo` metadata.
- Verification passed for `bun run typecheck`, `bun run test`, and `bun run build`.

## Related Plans

- **Previous**: `impl-plans/completed/x-gateway-full-api-coverage.md`
- **Next**: None
- **Depends On**: `impl-plans/active/x-gateway-registry-driven-routing.md`
