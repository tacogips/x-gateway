# Following Timeline Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/design-public-graphql-contract.md#query`, `design-docs/specs/command.md#project-owned-graphql-contract`, `design-docs/specs/architecture.md#capability-matrix-implementation-target`
**Created**: 2026-06-01
**Last Updated**: 2026-06-01

---

## Design Document Reference

**Source**: `design-docs/specs/design-public-graphql-contract.md`

### Summary

Implement stable public GraphQL `followingTimeline(...)` backed by capability `timeline.following`. The capability reads the authenticated account follow graph, fetches bounded recent timelines for followed accounts, merges posts by `createdAt` descending, applies existing promoted-post filtering, trims to `maxResults`, and returns the existing `PostPage` shape with author data, media handling, pageInfo, and nullable metrics including `impressionCount`.

### Scope

**Included**: complete existing partial metadata/schema/executor work, add adapter behavior, validate aggregate bounds, add SDK/GraphQL/CLI tests, and verify the read-only live smoke when credentials are available.

**Excluded**: writing X posts, committing credentials, replacing `homeTimeline`, implementing unreviewed raw X GraphQL passthrough, or claiming native upstream cursor semantics for merged aggregate pagination.

### Codex References

- Repo root: `/Users/taco/gits/tacogips/x-gateway`
- Consumer reference: `/Users/taco/gits/tacogips/rielflow/examples/x-follower-ai-business-digest`
- Live finding: direct `twitter-api-v2` OAuth1 `following()` and `userTimeline()` worked for the target account, while stable `homeTimeline(maxResults:50)` returned `posts:[]`.

---

## Modules

### 1. Public Contract and Stable Routing

#### `src/lib.ts`, `src/capability-metadata.ts`, `src/public-graphql-schema.ts`, `src/public-graphql-contract.ts`, `src/stable-capability-executor.ts`

**Status**: COMPLETED

```typescript
export type XGatewayFollowingTimelineOptions = Readonly<
  XGatewayTimelinePageOptions & {
    maxUsers?: number;
    maxResultsPerUser?: number;
  }
>;
```

**Checklist**:
- [x] Reconcile existing partial local diff without reverting user-authored unrelated changes.
- [x] Keep `timeline.following` metadata, planning readiness, public field registry, schema argument list, SDK type, and executor dispatch mechanically aligned.
- [x] Validate `followingTimeline` arguments, including positive bounded `maxUsers` and `maxResultsPerUser`.
- [x] Return a stable `PostPage` projection and reject unsupported arguments/selections explicitly.

### 2. REST Read Adapter

#### `src/capability-adapters.ts`

**Status**: COMPLETED

```typescript
type FollowingTimelineDefaults = Readonly<{
  maxUsers: number;
  maxResultsPerUser: number;
  maxResults: number;
}>;
```

**Checklist**:
- [x] Add `timelineFollowing(options: XGatewayFollowingTimelineOptions): Promise<XGatewayPostPage>` to REST OAuth1 and bearer read adapters where auth readiness allows it.
- [x] Fetch authenticated account identity, read following users with a conservative `maxUsers` limit, fetch each followed user's timeline with `maxResultsPerUser`, then merge by `createdAt` descending.
- [x] Reuse existing post mapping, media download, promoted filtering, and nullable metric behavior.
- [x] Use project-owned first-slice pagination semantics; do not pass through misleading upstream cursors as aggregate `nextToken`.
- [x] Emit explanatory validation/auth/rate-limit errors through existing error helpers.

### 3. Regression Tests

#### `src/lib.test.ts`, `src/capability-adapters.test.ts`

**Status**: COMPLETED

```typescript
type FollowingTimelineTestCase = Readonly<{
  query: string;
  expectedCapabilityId: "timeline.following";
  expectedPostOrder: readonly string[];
}>;
```

**Checklist**:
- [x] Add public GraphQL SDK tests for `followingTimeline` routing, projection, metrics, author fields, media options, and argument validation.
- [x] Add CLI GraphQL tests for the canonical field and reader-mode read-only behavior.
- [x] Add adapter tests for follow-graph fanout, recency merge, promoted filtering, empty follow graph, and conservative pageInfo.
- [x] Update capability metadata alignment tests to include `followingTimeline`.

### 4. Consumer Handoff Notes

#### `README.md` if present, `.agents/skills/*` only if public behavior text is affected, and `/Users/taco/gits/tacogips/rielflow/examples/x-follower-ai-business-digest`

**Status**: COMPLETED

```typescript
type ConsumerSwitch = Readonly<{
  from: "homeTimeline";
  to: "followingTimeline";
  verificationOnly: boolean;
}>;
```

**Checklist**:
- [x] Record whether this repository has public docs that need a `followingTimeline` mention; skip absent files such as missing `README.md`.
- [x] Do not edit the rielflow consumer example until x-gateway tests and smoke behavior pass, unless the implementation step is explicitly assigned that handoff.
- [x] Keep all live-smoke commands read-only and credential-free in git.

---

## Module Status

| Module | File Path | Status | Tests |
|--------|-----------|--------|-------|
| Public contract and routing | `src/lib.ts`, `src/capability-metadata.ts`, `src/public-graphql-schema.ts`, `src/public-graphql-contract.ts`, `src/stable-capability-executor.ts` | COMPLETED | `src/lib.test.ts` |
| REST read adapter | `src/capability-adapters.ts` | COMPLETED | `src/lib.test.ts` |
| Regression tests | `src/lib.test.ts`, `src/capability-adapters.test.ts` | COMPLETED | Bun tests |
| Consumer handoff notes | repo public docs, rielflow example reference | COMPLETED | live smoke only |

## Task Breakdown

### TASK-001: Reconcile Public Contract and Routing

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `src/lib.ts`, `src/capability-metadata.ts`, `src/public-graphql-schema.ts`, `src/public-graphql-contract.ts`, `src/stable-capability-executor.ts`
**Dependencies**: None

**Completion Criteria**:
- [x] `followingTimeline` maps only to `timeline.following`.
- [x] `maxResults`, `maxUsers`, `maxResultsPerUser`, `paginationToken`, `mediaRootDir`, `downloadMedia`, `forceDownload`, and `includePromoted` are accepted or rejected exactly as designed.
- [x] Capability metadata and public field alignment tests can include the new field.

### TASK-002: Implement Following Timeline Adapter

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `src/capability-adapters.ts`
**Dependencies**: TASK-001

**Completion Criteria**:
- [x] OAuth1 read adapter can fetch followed-account latest posts through `timelineFollowing`.
- [x] Bearer adapter behavior matches planning readiness and fails clearly if user-context access is unavailable.
- [x] Aggregate output is sorted, bounded, filtered, and shaped as `XGatewayPostPage`.
- [x] Aggregate `pageInfo.nextToken` is omitted unless a project-owned merged cursor is implemented in this task.

### TASK-003: Add Contract and Adapter Tests

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `src/lib.test.ts`, `src/capability-adapters.test.ts`
**Dependencies**: TASK-001, TASK-002

**Completion Criteria**:
- [x] SDK and CLI GraphQL tests cover successful `followingTimeline`.
- [x] Validation tests cover unsafe bounds and unexpected arguments.
- [x] Adapter tests cover follow graph fanout, merge order, empty results, promoted filtering, and metrics.

### TASK-004: Verify and Prepare Consumer Handoff

**Status**: Completed
**Parallelizable**: No
**Deliverables**: verification output and optional public-doc updates if a public docs target exists
**Dependencies**: TASK-003

**Completion Criteria**:
- [x] `bun run typecheck` passes.
- [x] `bun test` passes.
- [x] `bun run build` passes.
- [x] Read-only kinko-backed live smoke is attempted when credentials are available.
- [x] Consumer rielflow switch from `homeTimeline` to `followingTimeline` is explicitly left as the next handoff.

## Dependencies

| Feature | Depends On | Status |
|---------|------------|--------|
| TASK-001 public contract | Accepted Step 3 design review | COMPLETED |
| TASK-002 adapter | TASK-001 | COMPLETED |
| TASK-003 tests | TASK-001, TASK-002 | COMPLETED |
| TASK-004 verification/handoff | TASK-003 | COMPLETED |

## Parallelizable Tasks

No tasks are marked parallelizable. The feature touches coupled public contract, capability metadata, executor routing, adapter behavior, and shared tests; splitting writers across these files would create overlapping ownership.

## Verification Plan

- `bun run typecheck`
- `bun test`
- `bun run build`
- `kinko --path /Users/taco/gits/tacogips/rielflow exec --env X_GW_AUTH_MODE,X_GW_ACCOUNT_USERNAME,X_GW_CONSUMER_KEY,X_GW_CONSUMER_SECRET,X_GW_ACCESS_TOKEN,X_GW_ACCESS_TOKEN_SECRET -- bun run src/main.ts graphql query 'query { followingTimeline(maxResults: 50, maxUsers: 25, maxResultsPerUser: 5) { posts { id text createdAt metrics { impressionCount likeCount replyCount repostCount quoteCount bookmarkCount } author { id username name } } pageInfo { resultCount newestId oldestId nextToken } } }' --json`

## Completion Criteria

- [x] Stable public GraphQL exposes `followingTimeline(...)` and routes to `timeline.following`.
- [x] Adapter reads authenticated follow graph and followed-user timelines without writing posts.
- [x] Output uses existing `PostPage`, author, media, metric, and promoted filtering semantics.
- [x] Aggregate bounds and pagination behavior are explicit and defensible.
- [x] Typecheck, tests, build, and optional read-only live smoke are recorded.
- [x] No credentials or X write operations are introduced.

## Progress Log

### Session: 2026-06-01 00:00

**Tasks Completed**: Plan created after Step 3 accepted the design.
**Tasks In Progress**: None.
**Blockers**: None.
**Notes**: Implementation must treat existing partial local diff as input, not proof of completion.

### Session: 2026-06-01 18:13 JST

**Tasks Completed**: TASK-001, TASK-002, TASK-003, TASK-004.
**Tasks In Progress**: None.
**Blockers**: None.
**Notes**: Implemented stable public GraphQL `followingTimeline(...)` routing to `timeline.following`; added the REST read adapter fanout over authenticated following users and followed-user timelines; merged posts by `createdAt` descending; reused existing PostPage projection, metrics, media, and promoted filtering; rejected aggregate cursor passthrough until a project-owned merged cursor exists. Verification passed with `bun run typecheck`, `bun test`, `bun run build`, and `bun run format:check`. Read-only kinko live smoke for @yu_kawa_taco succeeded without write operations and returned an empty first aggregate page; direct diagnostic showed 25 followed accounts were readable but their first 25 sampled user timelines returned zero posts in the current credential context. Consumer example switch remains the next handoff.

## Related Plans

- **Previous**: `impl-plans/completed/x-gateway-canonical-public-graphql-interface.md`
- **Next**: None
- **Depends On**: accepted design updates in `design-docs/specs/architecture.md`, `design-docs/specs/command.md`, `design-docs/specs/design-public-graphql-contract.md`, and `design-docs/specs/notes.md`
