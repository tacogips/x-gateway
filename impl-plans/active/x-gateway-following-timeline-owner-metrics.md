# Following Timeline Owner-Only Metrics Fix Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#capability-matrix-implementation-target`, `design-docs/specs/design-public-graphql-contract.md#query`, `design-docs/specs/design-post-metrics.md#source-mapping`, `design-docs/specs/command.md#project-owned-graphql-contract`
**Created**: 2026-06-01
**Last Updated**: 2026-06-01

---

## Design Document Reference

**Source**: accepted Step 3 design review for workflow `codex-design-and-implement-review-loop`, issue-resolution mode.

### Summary

Fix `followingTimeline(...)` followed-account reads so they do not request owner-only X tweet field groups (`organic_metrics`, `promoted_metrics`) when fetching other users' timelines. The adapter must continue to request public fields, preserve public metric mapping, and keep `metrics.impressionCount` nullable when owner-only impression sources are unavailable.

### Scope

**Included**: REST read-adapter request option separation for followed-account timelines, focused mock assertions for outgoing `tweet.fields`, regression coverage for nullable `impressionCount`, and standard typecheck/test/build/format verification.

**Excluded**: changing the public GraphQL schema, changing `PostMetrics.impressionCount` type, storing live fetched posts, adding credentials to git, implementing owner-owned timeline metric expansion, or changing aggregate pagination semantics.

### Codex References

- Workflow ID: `codex-design-and-implement-review-loop`
- Step 3 review: accepted with `needs_revision=false`
- Repo root: `/Users/taco/gits/tacogips/x-gateway`
- Consumer reference: `/Users/taco/gits/tacogips/rielflow/examples/x-follower-ai-business-digest/workflow.json`
- Consumer boundary: behavioral reference only; do not copy implementation code from the rielflow repository.
- Live diagnosis reference: `client.v2.following` succeeds and `client.v2.userTimeline` for followed users returns posts with public fields, but adding `organic_metrics` caused upstream errors and zero tweets.

---

## Modules

### 1. Timeline Request Field Policy

#### `src/capability-adapters.ts`

**Status**: COMPLETED

```typescript
type RestTimelineMetricFieldPolicy = "default" | "public-only";

type RestTimelineRequestOptionsInput = Readonly<{
  requestInputs: PostPageRequestInputs;
  paginationTokenField: RestPaginationTokenField;
  metricFieldPolicy: RestTimelineMetricFieldPolicy;
}>;
```

**Checklist**:
- [x] Separate public-only timeline tweet fields from the current shared lookup/timeline fields.
- [x] Ensure `followingTimeline` followed-user `client.v2.userTimeline` calls omit `organic_metrics` and `promoted_metrics`.
- [x] Keep public metrics requested for followed-user timelines.
- [x] Preserve existing behavior for unrelated timeline/read paths unless they intentionally opt into the public-only policy.

### 2. FollowingTimeline Adapter Wiring

#### `src/capability-adapters.ts`

**Status**: COMPLETED

```typescript
type FollowingTimelineReadPolicy = Readonly<{
  followedUserTimelineMetricFields: "public-only";
  impressionCountWhenUnavailable: null;
}>;
```

**Checklist**:
- [x] Apply the public-only request-field policy only to followed-account user timeline fanout inside `timelineFollowing`.
- [x] Keep existing author, media, promoted filtering, merge ordering, and first-slice pageInfo semantics unchanged.
- [x] Confirm `mapPostPage` still maps missing owner-only metrics to nullable metric values rather than throwing.
- [x] Keep errors remediation-oriented if upstream timeline calls still fail for unrelated reasons.

### 3. Focused Regression Tests

#### `src/lib.test.ts`

**Status**: COMPLETED

```typescript
type TimelineCallFieldAssertion = Readonly<{
  kind: "user";
  userId: string;
  tweetFields: readonly string[];
}>;
```

**Checklist**:
- [x] Extend the twitter-api-v2 mock timeline call recording to capture requested `tweet.fields`.
- [x] Assert `followingTimeline` followed-user calls include `public_metrics`.
- [x] Assert `followingTimeline` followed-user calls exclude `organic_metrics` and `promoted_metrics`.
- [x] Add or update a regression case where followed-user payloads lack owner-only metrics and `metrics.impressionCount` is `null`.
- [x] Avoid changing fixtures to rely on live post content or credentials.

### 4. Verification and Documentation Check

#### `impl-plans/active/x-gateway-following-timeline-owner-metrics.md`, existing public docs if implementation changes documented behavior

**Status**: COMPLETED

```typescript
type VerificationCommand =
  | "bun run typecheck"
  | "bun test"
  | "bun run build"
  | "bun run format:check";
```

**Checklist**:
- [x] Run local verification commands and record results in the progress log.
- [x] Check whether public docs need a factual update after implementation; design docs already contain the accepted behavior.
- [x] Do not run or store live-smoke output unless explicitly needed; if run, keep it read-only and credential-free in git.

---

## Module Status

| Module | File Path | Status | Tests |
|--------|-----------|--------|-------|
| Timeline request field policy | `src/capability-adapters.ts` | COMPLETED | `src/lib.test.ts` |
| FollowingTimeline adapter wiring | `src/capability-adapters.ts` | COMPLETED | `src/lib.test.ts` |
| Focused regression tests | `src/lib.test.ts` | COMPLETED | Bun tests |
| Verification and documentation check | plan progress log, public docs if needed | COMPLETED | command verification |

## Task Breakdown

### TASK-001: Introduce Public-Only Timeline Field Policy

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `src/capability-adapters.ts`
**Dependencies**: Accepted Step 3 design review

**Completion Criteria**:
- [x] Request option construction can omit owner-only metric fields for selected timeline calls.
- [x] Public metrics remain requested for public-only followed-user timeline calls.
- [x] Existing unrelated post lookup and timeline callers retain their current field behavior unless deliberately changed by the implementation.

### TASK-002: Apply Policy to FollowingTimeline Fanout

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `src/capability-adapters.ts`
**Dependencies**: TASK-001

**Completion Criteria**:
- [x] `timelineFollowing` followed-user `client.v2.userTimeline` requests exclude `organic_metrics`.
- [x] `timelineFollowing` followed-user `client.v2.userTimeline` requests exclude `promoted_metrics`.
- [x] Aggregate sorting, trimming, author hydration, media handling, promoted filtering, and pageInfo output remain unchanged.
- [x] Missing owner-only metric groups do not prevent stable `PostPage` output.

### TASK-003: Add Request-Field and Nullable Metric Regression Tests

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `src/lib.test.ts`
**Dependencies**: TASK-001, TASK-002

**Completion Criteria**:
- [x] Mock timeline call records include requested tweet fields.
- [x] `followingTimeline` SDK test proves followed-user calls request `public_metrics` only from the metric field groups.
- [x] Regression output proves `metrics.impressionCount` remains `null` when public fields are present but owner-only metrics are absent.
- [x] Existing contract tests continue to pass without storing live posts or credentials.

### TASK-004: Verify, Format, and Log Progress

**Status**: Completed
**Parallelizable**: No
**Deliverables**: verification output, updated progress log in this plan
**Dependencies**: TASK-003

**Completion Criteria**:
- [x] `bun run typecheck` passes.
- [x] `bun test` passes.
- [x] `bun run build` passes.
- [x] `bun run format:check` passes.
- [x] Progress log records completed tasks, verification results, and any skipped live-smoke rationale.

## Dependencies

| Feature | Depends On | Status |
|---------|------------|--------|
| TASK-001 field policy | Accepted Step 3 design review | COMPLETED |
| TASK-002 followingTimeline wiring | TASK-001 | COMPLETED |
| TASK-003 regression tests | TASK-001, TASK-002 | COMPLETED |
| TASK-004 verification | TASK-003 | COMPLETED |

## Parallelizable Tasks

No tasks are marked parallelizable. TASK-001 and TASK-002 both write `src/capability-adapters.ts`, while TASK-003 depends on the final request shape and writes shared mock/test state in `src/lib.test.ts`.

## Verification Plan

- `bun run typecheck`
- `bun test`
- `bun run build`
- `bun run format:check`
- Optional read-only live smoke only if explicitly required and credentials are available through the approved local secret mechanism; do not store fetched posts or credentials in git.

## Completion Criteria

- [x] `followingTimeline` followed-account timeline reads do not request `organic_metrics`.
- [x] `followingTimeline` followed-account timeline reads do not request `promoted_metrics`.
- [x] Followed-account reads still request `public_metrics`.
- [x] Stable metrics mapping preserves nullable `metrics.impressionCount`.
- [x] Focused tests assert outgoing field behavior, not only response shape.
- [x] Typecheck, tests, build, and format verification pass.
- [x] No fetched live posts or credentials are added to git.

## Progress Log

### Session: 2026-06-01

**Tasks Completed**: Plan created after Step 3 accepted the design.
**Tasks In Progress**: None.
**Blockers**: None.
**Notes**: Later implementation must treat existing completed `impl-plans/active/x-gateway-following-timeline.md` as historical baseline and this plan as the active owner-only metrics fix.

### Session: 2026-06-01 Step 6 Implementation

**Tasks Completed**: TASK-001, TASK-002, TASK-003, TASK-004.
**Tasks In Progress**: None.
**Blockers**: None.
**Notes**: Added a `public-only` REST timeline metric field policy in `src/capability-adapters.ts` and applied it only to followed-account `timelineFollowing` fanout. Updated `src/lib.test.ts` to record outgoing `tweet.fields`, assert followed-user timeline calls include `public_metrics` while excluding `organic_metrics` and `promoted_metrics`, and verify `metrics.impressionCount` remains `null` when owner-only metric groups are absent. No live smoke was run and no live posts or credentials were stored.
**Verification**: `bun run typecheck` passed; `bun test` passed with 121 tests; `bun run build` passed; `bun run format:check` passed.

## Related Plans

- **Previous**: `impl-plans/active/x-gateway-following-timeline.md`
- **Depends On**: accepted design updates in `design-docs/specs/architecture.md`, `design-docs/specs/design-public-graphql-contract.md`, `design-docs/specs/design-post-metrics.md`, `design-docs/specs/command.md`, and `design-docs/references/README.md`
