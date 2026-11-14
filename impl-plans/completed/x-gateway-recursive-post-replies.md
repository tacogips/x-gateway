# X Gateway Recursive Post Replies Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/design-recursive-post-replies.md
**Created**: 2026-04-05
**Last Updated**: 2026-04-05

---

## Design Document Reference

**Source**:
- design-docs/specs/design-recursive-post-replies.md
- design-docs/specs/design-post-replies-query.md
- design-docs/specs/design-public-graphql-contract.md
- design-docs/specs/architecture.md

### Summary
Add `Post.replies(...)` as the canonical recursive nested GraphQL field backed by the existing stable `post.replies` capability, including nested field-argument parsing, schema validation, bounded nested execution, regression coverage, and removal of the redundant top-level `postReplies(...)` field.

### Scope
**Included**:
- nested `replies(...)` field on `Post`
- nested selection argument parsing and validation
- bounded nested `post.replies` execution during GraphQL result hydration
- removal of top-level `postReplies(...)` from the stable public GraphQL contract
- SDK and CLI regression coverage
- design and implementation tracking updates

**Excluded**:
- arbitrary nested capability execution for non-reply fields
- batching multiple reply lookups into one upstream request
- full conversation-tree semantics beyond explicit recursive direct-reply traversal

---

## Tasks

### TASK-001: Recursive Replies Design
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `design-docs/specs/design-recursive-post-replies.md`
- related public design doc updates

**Completion Criteria**:
- [x] Recursive `Post.replies(...)` semantics are specified
- [x] Bounded nested execution model is documented
- [x] Public contract limitations remain explicit

### TASK-002: Parser and Contract Validation
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/public-graphql-parser.ts`
- `src/public-graphql-schema.ts`
- `src/public-graphql-contract.ts`

**Completion Criteria**:
- [x] Nested field arguments parse correctly
- [x] `Post.replies(...)` exists in the public schema
- [x] Unsupported nested arguments and missing nested selections fail explicitly

### TASK-003: Nested Capability Execution
**Status**: Completed
**Parallelizable**: No (depends on TASK-001, TASK-002)
**Deliverables**:
- `src/lib.ts`

**Completion Criteria**:
- [x] Recursive replies hydrate through stable `post.replies`
- [x] Nested reply expansion limit is enforced per request
- [x] Projection still runs against the stable payload schema after hydration

### TASK-004: Verification and Plan Tracking
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`
- `impl-plans/README.md`
- `impl-plans/PROGRESS.json`

**Completion Criteria**:
- [x] Recursive SDK coverage exists
- [x] Recursive CLI coverage exists
- [x] Nested validation coverage exists
- [x] Typecheck, tests, and build pass

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Recursive reply design | `design-docs/specs/design-recursive-post-replies.md` | COMPLETED | N/A |
| Parser and schema | `src/public-graphql-parser.ts`, `src/public-graphql-schema.ts` | COMPLETED | Covered |
| Contract and nested execution | `src/public-graphql-contract.ts`, `src/lib.ts` | COMPLETED | Covered |
| Verification | `src/lib.test.ts` | COMPLETED | Covered |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001, TASK-002 |
| TASK-004 | TASK-002, TASK-003 |

## Completion Criteria

- [x] `Post.replies(...)` is part of the stable project-owned GraphQL contract
- [x] Nested reply traversal works recursively through `PostPage.posts`
- [x] Top-level `postReplies(...)` is removed from the stable public contract with migration guidance
- [x] Nested execution remains bounded and explicit
- [x] Verification passes across SDK, CLI, typecheck, and build

## Progress Log

### Session: 2026-04-05 19:10 JST
**Tasks Completed**: TASK-001, TASK-002, TASK-003, TASK-004
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- The previous `postReplies(postId: ...)` slice exposed only top-level direct-reply lookup.
- This iteration makes `Post.replies(...)` the canonical public surface and removes the redundant top-level field.
- Nested reply traversal is intentionally bounded to keep the N+1 cost explicit and predictable.

### Session: 2026-04-05 19:15 JST
**Tasks Completed**: Contract removal follow-up
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Removed the remaining top-level `postReplies(...)` field from the public schema and field registry.
- Added explicit migration guidance that rewrites callers toward `post(id: "...") { replies(...) { ... } }`.
- Updated capability metadata so `post.replies` remains implemented without advertising a redundant top-level public operation name.
