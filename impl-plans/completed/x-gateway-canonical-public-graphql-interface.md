# Canonical Public GraphQL Interface Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#stable-contract-with-internal-adapters`, `design-docs/specs/command.md#project-owned-graphql-contract`, `design-docs/specs/design-public-graphql-contract.md`
**Created**: 2026-03-08
**Last Updated**: 2026-04-05

## Summary

Keep the project-owned `graphql` surface canonical across CLI and SDK: `x-gateway graphql query '<query>'` in the CLI and `createXGatewayClient().graphqlQuery({ query })` in the SDK.

This plan covers contract normalization, routing preservation, and messaging/documentation cleanup for the current baseline:

- `accountMe`
- `post(id: ID!)`
- `createPost(text: String!, attachments: [PostAttachmentInput!])`
- `deletePost(postId: ID!)`
- `replyToPost(text: String!, replyToPostId: ID!, attachments: [PostAttachmentInput!])`
- `quotePost(text: String!, quotedPostId: ID!, attachments: [PostAttachmentInput!])`
- `repostPost(postId: ID!)`
- `unrepostPost(postId: ID!)`

## Scope

Included:

- Canonical project-owned GraphQL field and argument names
- Canonical project-owned response shapes for approved fields
- Capability metadata alignment with canonical public names
- CLI/docs positioning so `graphql query` / `graphqlQuery(...)` are clearly primary
- Tests for request parsing, execution, and route preservation

Not included in this iteration:

- Multi-field GraphQL documents
- GraphQL variables, fragments, aliases, or directives
- New capability families beyond the current stable baseline
- Removal of existing convenience commands

## Modules

### 1. Public Contract Registry

#### `src/capability-metadata.ts`

```typescript
type CapabilityDescriptor = Readonly<{
  id: string;
  publicOperationName?: string;
  surfaceCategory: "stable-contract" | "deferred";
}>;
```

Checklist:

- [x] Canonical public operation names align with intended schema
- [x] post mutation capabilities advertise `postId`-based operations where applicable

### 2. Public GraphQL Planner

#### `src/public-graphql-contract.ts`

```typescript
type PlannedPublicGraphqlQuery = Readonly<{
  capabilityId: StableCapabilityId;
  fieldName: string;
  buildCapabilityInput: (
    args: Readonly<Record<string, PublicGraphqlValue>>,
  ) => unknown;
}>;
```

Checklist:

- [x] `deletePost(postId: ...)` maps to `post.delete`
- [x] `repostPost(postId: ...)` maps to `post.repost`
- [x] `unrepostPost(postId: ...)` maps to `post.unrepost`
- [x] Attachment-aware mutation arguments map to stable posting capability input
- [x] Stable response shaping remains capability-owned

### 3. CLI and Documentation Positioning

#### `src/cli.ts`
#### `design-docs/specs/architecture.md`
#### `design-docs/specs/command.md`
#### `design-docs/specs/design-public-graphql-contract.md`

```typescript
type CliSurface = "full" | "reader";
```

Checklist:

- [x] Usage text states `graphql query` is the primary public interface
- [x] SDK naming matches the canonical `graphql` terminology
- [x] Removed CLI convenience commands remain outside the supported public surface
- [x] Canonical schema names in docs match implementation

### 4. Verification

#### `src/lib.test.ts`
#### `src/capability-adapters.test.ts`

```typescript
type XGatewayGraphqlQueryOptions = Readonly<{
  query: string;
  traceId?: string | undefined;
}>;
```

Checklist:

- [x] SDK execution tests cover canonical query/mutation names
- [x] Registry coherence tests assert canonical public operation names
- [x] Public schema validation rejects unsupported arguments and unsupported selection fields with actionable errors
- [x] CLI end-to-end smoke checks against a live configured environment

## Dependencies

| Task | Depends On | Status |
|------|------------|--------|
| Canonical naming updates | None | Completed |
| CLI/docs repositioning | Canonical naming updates | Completed |
| Automated verification | Canonical naming updates | Completed |
| Schema validation hardening | Canonical naming updates | Completed |
| Live smoke validation | Configured credentials | Completed |

## Completion Criteria

- [x] Public GraphQL schema is simplified and project-owned
- [x] Canonical schema no longer requires X document ids or feature toggles
- [x] Capability mapping remains decoupled from upstream transport choice
- [x] Existing stable account/post behavior remains routed through the shared capability executor
- [x] Unsupported arguments and unsupported selection fields are rejected explicitly by the project-owned GraphQL validator
- [x] Automated tests pass
- [x] Live smoke validation completed or explicitly blocked by missing credentials

## Progress Log

### Session: 2026-03-08 13:16 JST

**Tasks Completed**: Design review, canonical contract naming update, CLI/docs repositioning, automated test updates
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification depends on configured credentials in the current environment
**Notes**: The pre-existing architecture already separated public GraphQL planning from raw upstream GraphQL, but the canonical contract still used older field names (`likedPosts`, mutation `id` arguments) and docs still treated stable command groups as primary peers instead of transition surfaces beneath `api request`. `bun test` and `bunx tsc --noEmit` now pass after the canonical schema and messaging updates.

### Session: 2026-03-08 13:42 JST

**Tasks Completed**: Contract review correction for `likes` response shaping, SDK/CLI verification updates
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification depends on configured credentials in the current environment
**Notes**: Review found that the rename-only pass still leaked the adapter's bare likes array into the public contract. The owned GraphQL schema now explicitly returns `likes { posts }`, which keeps the public shape decoupled from the internal capability result while preserving the same `likes.list` capability and auth routing.

### Session: 2026-03-08 13:52 JST

**Tasks Completed**: Canonical contract validation hardening, migration-regression tests
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification depends on configured credentials and network access in the current environment
**Notes**: Architecture review confirmed the repository now matches the intended split: `api request` is the canonical project-owned GraphQL surface, stable capability execution remains the core abstraction, and raw `graphql request` stays isolated as an escape hatch. This session hardened migration ergonomics by making deprecated `likedPosts` and legacy mutation `id` arguments fail with explicit canonical replacements instead of generic validation errors.

### Session: 2026-03-08 13:24 JST

**Tasks Completed**: Canonical mutation regression coverage review
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification depends on configured credentials and network access in the current environment
**Notes**: Continued review found the architecture and implementation already matched the intended product split, but direct public-GraphQL regression coverage still underrepresented the canonical mutation family. Added SDK and CLI tests for `replyToPost`, `quotePost`, `repostPost`, and `unrepostPost` through `api request`, plus migration-error coverage for deprecated `id` arguments on repost/unrepost mutations. Re-ran `bun test src/lib.test.ts src/capability-adapters.test.ts` and `bunx tsc --noEmit`.

### Session: 2026-03-08 13:26 JST

**Tasks Completed**: Continued architecture review and CLI migration guidance hardening
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification depends on configured credentials and network access in the current environment
**Notes**: Continued review confirmed the implemented architecture already matches the intended purpose: the public contract is project-owned GraphQL over stable capability execution with capability-aware auth/transport routing. Follow-up hardening removed the remaining CLI error guidance that pointed callers at raw `graphql request` as the default fallback, so command remediation now names `api request` as the canonical surface and keeps raw GraphQL explicitly secondary.

### Session: 2026-03-08 14:06 JST

**Tasks Completed**: Architecture re-review and gap identification for public-schema validation
**Tasks In Progress**: Public GraphQL validation hardening
**Blockers**: Live upstream verification still depends on configured credentials and network access in the current environment
**Notes**: Review found the adapter layering itself is correct, but the project-owned GraphQL contract still tolerated unsupported arguments and unsupported selection fields by ignoring them. This iteration tightens validation so the owned schema behaves like an explicit contract rather than a permissive projection helper.

### Session: 2026-03-08 14:13 JST

**Tasks Completed**: Public GraphQL validation hardening, regression test expansion
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification still depends on configured credentials and network access in the current environment
**Notes**: The public contract now rejects transport-shaped extra arguments, rejects unsupported selection fields, requires nested selections for object fields, and rejects nested selections on scalars. Re-ran `bun test src/lib.test.ts src/capability-adapters.test.ts` and `bunx tsc --noEmit`.

### Session: 2026-03-08 13:39 JST

**Tasks Completed**: Continuation review of auth-routing remediation messaging, regression coverage hardening
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification still depends on configured credentials and network access in the current environment
**Notes**: Architecture review still matches the intended canonical public GraphQL split. Follow-up review found one remaining messaging issue: bearer-only failures for stable posting capabilities still read like raw GraphQL might be a reviewed fallback. Capability metadata and regression coverage now state explicitly that no reviewed bearer-mode stable fallback exists for those write capabilities; raw `graphql request` remains a separate intentional escape hatch only. Re-ran `bun test src/lib.test.ts src/capability-adapters.test.ts` and `bunx tsc --noEmit`.

### Session: 2026-03-08 13:32 JST

**Tasks Completed**: Architecture re-review, canonical `api request` regression coverage expansion
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification still depends on configured credentials and network access in the current environment
**Notes**: Continued review confirmed the architecture already matches the intended product split, but canonical public-GraphQL verification still under-covered `post` fetch and mixed-auth `likes` routing compared with the older convenience surfaces. Added SDK and CLI regression coverage proving `api request` preserves the reviewed OAuth1-over-broken-bearer preference for `likes`, plus direct canonical `post(id: ...)` fetch coverage. Re-ran `bun test src/lib.test.ts src/capability-adapters.test.ts` and `bunx tsc --noEmit`.

### Session: 2026-03-08 13:34 JST

**Tasks Completed**: Public contract hardening follow-up for argument and projection strictness
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification still depends on configured credentials and network access in the current environment
**Notes**: Review found one remaining validation gap: `accountMe` still tolerated unexpected arguments even though the canonical schema defines none. This session closed that hole and tightened projection behavior so requested stable fields now fail loudly if the normalized payload omits them or returns a scalar where an object selection was requested, preventing silent drift between reviewed adapters and the project-owned GraphQL contract.

### Session: 2026-03-08 13:38 JST

**Tasks Completed**: Continuation review of branch diff, runtime remediation positioning fix
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification still depends on configured credentials and network access in the current environment
**Notes**: Continued review found one remaining positioning drift in `src/lib.ts`: unsupported stable-contract field routing still suggested reviewed convenience commands before reiterating `api request` as canonical. Updated the remediation so stable project-owned GraphQL remains primary and raw `graphql request` stays explicitly secondary even in unsupported-capability messaging. Re-ran targeted verification after the patch.

### Session: 2026-03-08 14:24 JST

**Tasks Completed**: Public GraphQL parser diagnostics hardening, unsupported-syntax regression coverage
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification still depends on configured credentials and network access in the current environment
**Notes**: Continued branch review found that unsupported GraphQL syntax such as operation names, aliases, directives, and fragments still failed through generic parser fallout instead of explicit stable-contract diagnostics. Hardened `src/public-graphql-parser.ts` so the project-owned schema now rejects those forms with actionable validation messages, then expanded regression coverage in `src/lib.test.ts` and re-ran `bun test src/lib.test.ts src/capability-adapters.test.ts` plus `bunx tsc --noEmit`.

### Session: 2026-03-08 13:49 JST

**Tasks Completed**: Continuation architecture review, branch diff validation, plan/progress maintenance
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification still depends on configured credentials and network access in the current environment
**Notes**: Re-reviewed the current diff against the intended product direction and did not find a new design or implementation mismatch. The canonical public surface remains `api request` with a project-owned schema, stable capability execution remains the shared abstraction beneath CLI/SDK/public GraphQL entrypoints, and raw `graphql request` remains clearly secondary. Re-ran `bun test src/lib.test.ts src/capability-adapters.test.ts` and `bunx tsc --noEmit`; both still pass. This iteration only updates progress tracking because no further corrective code changes were warranted from the review.

### Session: 2026-03-08 13:45 JST

**Tasks Completed**: Public response-shape validation hardening, adapter-drift regression coverage
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification still depends on configured credentials and network access in the current environment
**Notes**: Continued review found one remaining stable-contract gap after request validation hardening: response projection still allowed object/list payloads to leak through scalar public fields if an adapter drifted. `src/public-api-contract.ts` now carries the public selection schema through execution and validates scalar/object/list output shapes during projection, with new regression coverage in `src/lib.test.ts`. Re-ran `bun test src/lib.test.ts src/capability-adapters.test.ts` and `bunx tsc --noEmit`.

### Session: 2026-03-08 13:48 JST

**Tasks Completed**: Architecture/design re-review, documentation consistency cleanup, verification rerun
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification still depends on configured credentials and network access in the current environment
**Notes**: Re-reviewed the current branch against the intended architecture and confirmed the implementation already matches the required direction: `api request` is the project-owned canonical GraphQL surface, stable capability routing remains the core abstraction, transport choice stays internal, and raw `graphql request` remains secondary. The remaining inconsistency was a stale command-design note that still suggested deferred workflows should fall back to raw GraphQL; that guidance now preserves `api request` as canonical. Re-ran `bun test src/lib.test.ts src/capability-adapters.test.ts` and `bunx tsc --noEmit`.

### Session: 2026-03-08 14:33 JST

**Tasks Completed**: Continuation diff review, auth diagnostics truthfulness fix, regression coverage update
**Tasks In Progress**: Live upstream verification only
**Blockers**: Live upstream verification still depends on configured credentials and network access in the current environment
**Notes**: Continued review of the in-progress branch did not reveal a new architectural mismatch: the implementation still matches the intended split between canonical project-owned `api request`, stable capability routing, and raw GraphQL escape hatch behavior. This session found one remaining correctness drift in `authScopes()` where the mixed-auth notes still claimed `likes.list` could fall back to bearer reads. Updated the diagnostic text to match the reviewed OAuth1-only `likes` route and added regression coverage in `src/lib.test.ts`. Re-ran `bun run typecheck`, `bun test`, and `bun run build`.

### Session: 2026-03-08 22:35 JST

**Tasks Completed**: Canonical contract truthfulness correction for deferred likes support
**Tasks In Progress**: Live upstream verification only for the supported account/post baseline
**Blockers**: A reviewed live liked-post adapter route is still missing
**Notes**: Continued review found an actual contract mismatch: `likes` was still exposed as canonical public GraphQL even though the live adapter path is known to fail with upstream HTTP 400 in real CLI usage. The plan is now corrected to keep the project-owned canonical surface truthful: `api request` remains the canonical interface for the supported account/post baseline, attachment-backed post mutations remain included, and liked-post lookup is explicitly deferred until a verified route is restored.

### Session: 2026-03-08 22:50 JST

**Tasks Completed**: Deferred likes SDK-surface truthfulness correction
**Tasks In Progress**: Live upstream verification only for the supported account/post baseline
**Blockers**: A reviewed live liked-post adapter route is still missing, and live verification is blocked by credentials/network policy in this environment
**Notes**: Continued diff review found the stable SDK still advertised `likesList()` even after design, CLI, capability metadata, and public GraphQL contract updates had deferred liked-post lookup. Removed the helper from the public client surface and updated regression coverage so the implementation no longer exposes a known-broken stable capability through the SDK.

### Session: 2026-03-08 23:20 JST

**Tasks Completed**: Architecture/design coherence re-review, active-plan truthfulness cleanup
**Tasks In Progress**: Live upstream verification only for the supported account/post baseline
**Blockers**: Live upstream verification is still blocked by missing reviewed credentials and network access in this environment
**Notes**: The implemented repository state matches the intended architecture: `api request` is the canonical project-owned GraphQL interface, stable capability routing remains the shared executor boundary, attachment-backed post mutations are implemented through internal OAuth1 media upload, and raw `graphql request` remains an explicit low-level escape hatch only. This plan entry corrects stale historical wording from earlier branch iterations that mentioned `likes` as an active canonical field; that capability is still deferred and intentionally excluded from the stable public GraphQL contract until a reviewed live route is verified.

### Session: 2026-03-08 23:29 JST

**Tasks Completed**: Stable SDK surface cleanup, verification rerun
**Tasks In Progress**: Live upstream verification only for the supported account/post baseline
**Blockers**: Live upstream verification is still blocked by missing reviewed credentials and network access in this environment
**Notes**: Continued review did not reveal an architecture mismatch, but it did find one remaining stale public-SDK artifact: `src/lib.ts` still exported liked-post option/result types even though `likes.list` is intentionally deferred from the reviewed stable contract. Removed those exports so the TypeScript surface no longer suggests a supported stable liked-post workflow, then re-ran `bun run typecheck`, `bun test`, and `bun run build`.

### Session: 2026-04-05 18:35 JST

**Tasks Completed**: Active-plan terminology refresh, capability-inspection hardening
**Tasks In Progress**: Live upstream verification only for the supported account/post baseline
**Blockers**: Live upstream verification is still blocked by missing reviewed credentials and network access in this environment
**Notes**: Re-reviewed the current repository state against the intended product direction and confirmed that the architecture remains aligned: the project-owned `graphql` contract is the supported public surface, stable capability routing remains the shared execution boundary, and unsupported workflows are rejected instead of falling through to a raw GraphQL peer surface. This session updates the still-active plan wording to match the current CLI/SDK terminology and adds a small SDK/CLI hardening fix so capability inspection trims surrounding whitespace instead of failing on an exact-string mismatch.

### Session: 2026-04-05 18:55 JST

**Tasks Completed**: Live canonical GraphQL smoke validation
**Tasks In Progress**: None
**Blockers**: None for the supported account/post baseline; deferred `likes.list` remains tracked separately
**Notes**: Verified the canonical project-owned GraphQL CLI against the configured live environment through both `bun run src/main.ts graphql query 'query { accountMe { id username } }' --json` and `bun run src/main-reader.ts graphql query 'query { accountMe { id username } }' --json`. Both commands returned successful `accountMe` results for the configured account, so the remaining live-smoke item for this plan is now complete.
