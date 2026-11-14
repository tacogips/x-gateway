# X Gateway Promotion Status And Read Adapter Hardening Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#stable-contract-with-internal-adapters`, `design-docs/specs/architecture.md#module-boundaries-planned`
**Created**: 2026-04-05
**Last Updated**: 2026-04-05

---

## Design Document Reference

**Source**:
- `design-docs/specs/architecture.md`

### Summary
Review the 2026-04-05 GraphQL-contract changes for correctness and maintainability. The architecture still matches the intended product direction, so this slice hardens the existing design instead of introducing a new one: fix promotion-status classification when upstream metric payloads contain zero values, remove duplicated REST read-adapter logic, and add regression coverage for the overlooked case.

### Scope
**Included**:
- promotion-status truthfulness fix for zero-valued promoted and organic metric payloads
- DRY extraction for duplicated REST read-adapter methods shared by OAuth1 and bearer reads
- regression coverage for zero-metric promoted filtering and includePromoted behavior
- verification with `bun test`, `bun run typecheck`, and `bun run build`

**Excluded**:
- public GraphQL schema changes
- capability registry surface changes
- additional capability families or transport strategies

---

## Tasks

### TASK-001: Promotion Truthfulness Hardening
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/capability-adapters.ts`
- `src/lib.test.ts`

**Completion Criteria**:
- [x] Zero-valued promoted metrics still classify a post as `PROMOTED`
- [x] Zero-valued organic metrics still classify a post as `NOT_PROMOTED`
- [x] Default promoted-post filtering remains truthful for zero-metric payloads

### TASK-002: Shared Read Adapter Extraction
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/capability-adapters.ts`

**Completion Criteria**:
- [x] OAuth1 and bearer read adapters reuse one reviewed implementation for timeline and post-read methods
- [x] Adapter behavior stays unchanged across post lookup, replies, and timeline reads
- [x] The extracted helper keeps auth-specific behavior limited to the parts that actually differ

### TASK-003: Verification
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`

**Completion Criteria**:
- [x] Regression tests cover zero-metric promoted filtering and explicit includePromoted reads
- [x] `bun test src/lib.test.ts` passes
- [x] `bun run typecheck` passes
- [x] `bun run build` passes

---

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Promotion classification hardening | `src/capability-adapters.ts` | COMPLETED | Covered |
| Shared read-adapter extraction | `src/capability-adapters.ts` | COMPLETED | Covered |
| Regression coverage | `src/lib.test.ts` | COMPLETED | Covered |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001, TASK-002 |

## Completion Criteria

- [x] Architecture re-review confirmed no design mismatch for this iteration
- [x] Promotion classification is truthful for zero-valued metric payloads
- [x] Duplicated read-adapter logic is consolidated without behavior drift
- [x] Verification passes for tests, type checking, and build output

## Progress Log

### Session: 2026-04-05 20:12 JST
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Re-reviewed the current 2026-04-05 architecture and did not find a design mismatch. The canonical public GraphQL contract over stable capability routing remains aligned with the intended purpose.
- Review found one correctness issue in the new promoted-post handling: zero-valued promoted metrics were being treated as absent, which could misclassify promoted payloads as `UNKNOWN` and let them bypass default filtering.
- Fixed the classification logic, extracted the duplicated OAuth1/bearer read-adapter methods into one shared helper, and added regression tests for zero-metric promoted timeline and post reads.

### Session: 2026-04-05 20:40 JST
**Tasks Completed**: Continuation review hardening
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Continued review did not reveal an architecture/design mismatch, so no new design document or plan was required for this iteration.
- Found one remaining quality gap inside the shared read-adapter extraction: timeline/post-page methods still repeated the same pagination and post-read option validation pattern even after the auth-level DRY pass.
- Consolidated that validation into shared helpers in `src/capability-adapters.ts` and added a direct regression test proving zero-metric promoted top-level post lookups are still filtered unless `includePromoted: true` is explicitly requested.

## Related Plans

- **Previous**: `impl-plans/completed/x-gateway-recursive-post-replies.md`
- **Next**: None
- **Depends On**: `impl-plans/completed/x-gateway-recursive-post-replies.md`, `impl-plans/completed/x-gateway-post-metrics-nullable.md`
