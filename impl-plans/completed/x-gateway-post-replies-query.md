# X Gateway Post Replies Query Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/design-post-replies-query.md
**Created**: 2026-04-05
**Last Updated**: 2026-04-05

---

## Design Document Reference

**Source**:
- design-docs/specs/design-post-replies-query.md
- design-docs/specs/design-public-graphql-contract.md
- design-docs/specs/architecture.md
- design-docs/specs/command.md

### Summary
Historical slice that added a reviewed stable reply-listing capability through the top-level `postReplies(postId: ..., maxResults: ..., paginationToken: ...)` field. This public field has since been removed in favor of canonical nested `Post.replies(...)`.

### Scope
**Included**:
- stable capability metadata and planning for direct reply lookup
- REST adapter execution through the reviewed recent-search path
- public GraphQL schema and contract wiring for `postReplies`
- CLI and SDK coverage through the shared GraphQL entrypoint
- regression tests and public skill/doc updates

**Excluded**:
- nested `Post.replies(...)` child-field execution
- recursive thread traversal
- conversation-tree materialization
- ranking or hydration rules beyond existing `PostPage` behavior

---

## Tasks

### TASK-001: Design and Registry Extension
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `design-docs/specs/design-post-replies-query.md`
- `design-docs/specs/design-public-graphql-contract.md`
- `src/capability-metadata.ts`

**Completion Criteria**:
- [x] Direct-reply semantics are specified
- [x] Stable capability id and public operation name are registered
- [x] Auth/readiness behavior is documented

### TASK-002: Stable Capability Execution and Adapter Wiring
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/lib.ts`
- `src/stable-capability-executor.ts`
- `src/capability-adapters.ts`

**Completion Criteria**:
- [x] Stable executor accepts `post.replies`
- [x] OAuth1 and bearer read adapters execute direct-reply lookup
- [x] Input validation keeps reply lookup scoped to a single post id token

### TASK-003: Public GraphQL Contract Exposure
**Status**: Completed
**Parallelizable**: No (depends on TASK-001, TASK-002)
**Deliverables**:
- `src/public-graphql-schema.ts`
- `src/public-graphql-contract.ts`

**Completion Criteria**:
- [x] `postReplies` is part of the owned GraphQL schema
- [x] `postReplies` maps to `post.replies`
- [x] `PostPage` projection and validation rules match existing page fields

### TASK-004: Verification and Public Docs
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`
- `.agents/skills/x-read-via-reader/SKILL.md`
- `impl-plans/README.md`
- `impl-plans/PROGRESS.json`

**Completion Criteria**:
- [x] SDK and CLI regression coverage exists for `postReplies`
- [x] Capability metadata alignment tests include the new public field
- [x] Public read-skill examples mention `postReplies`
- [x] Plan/progress tracking is updated

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Reply-listing design | `design-docs/specs/design-post-replies-query.md` | COMPLETED | N/A |
| Capability metadata and planner | `src/capability-metadata.ts` | COMPLETED | Covered |
| Stable executor and adapters | `src/stable-capability-executor.ts`, `src/capability-adapters.ts` | COMPLETED | Covered |
| Public GraphQL contract | `src/public-graphql-schema.ts`, `src/public-graphql-contract.ts` | COMPLETED | Covered |
| Verification and public docs | `src/lib.test.ts`, `.agents/skills/x-read-via-reader/SKILL.md` | COMPLETED | Covered |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001, TASK-002 |
| TASK-004 | TASK-002, TASK-003 |

## Completion Criteria

- [x] Stable direct-reply lookup is part of the reviewed capability set
- [x] Historical iteration exposed `postReplies` as a top-level page query
- [x] CLI and SDK both reach the same shared capability execution path
- [x] Tests and project docs cover the delivered slice

## Progress Log

### Session: 2026-04-05 18:37 JST
**Tasks Completed**: TASK-001, TASK-002, TASK-003, TASK-004
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Chose a top-level `postReplies` query instead of nested `Post.replies(...)` because the current public GraphQL implementation is top-level capability planning plus projection-only nested fields.
- Implemented direct-reply semantics through the reviewed recent-search adapter route using `in_reply_to_tweet_id:<postId>`.
- Kept the reply-list result shape aligned with the existing `PostPage` contract so pagination, media download flags, and promoted-post filtering behave consistently with existing page fields.
