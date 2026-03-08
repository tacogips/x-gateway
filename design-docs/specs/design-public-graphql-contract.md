# Public GraphQL Contract Design

This document defines the project-owned GraphQL-shaped request contract for `x-gateway`.

## Goal

Provide a stable GraphQL-shaped public contract that expresses user intent without exposing raw X web GraphQL transport details such as document ids, operation names, feature flags, or rollout toggles.

## Contract Rules

- This contract is owned by `x-gateway`, not by X web GraphQL.
- Top-level fields map to stable project capabilities.
- Transport selection is internal and decided by the capability planner.
- Raw `graphql request` remains a separate low-level escape hatch.
- Unsupported project fields must fail with `UNSUPPORTED` or `VALIDATION_ERROR` without silently falling through to raw upstream GraphQL.
- Capability inventory and diagnostics must continue to mark raw `graphql.request` as an escape hatch rather than part of this stable public contract.

## Initial Public Fields

### Query

- `accountMe`
  - maps to capability `account.me`
- `post(id: ID!)`
  - maps to capability `post.get`
- `likedPosts(userId: ID!, limit: Int)`
  - maps to capability `likes.list`
  - stable baseline uses the capability planner and a reviewed REST-backed adapter

### Mutation

- `createPost(text: String!)`
  - maps to capability `post.create`
- `deletePost(id: ID!)`
  - maps to capability `post.delete`
- `replyToPost(text: String!, replyToPostId: ID!)`
  - maps to capability `post.reply`
- `quotePost(text: String!, quotedPostId: ID!)`
  - maps to capability `post.quote`
- `repostPost(id: ID!)`
  - maps to capability `post.repost`
- `unrepostPost(id: ID!)`
  - maps to capability `post.unrepost`

## Planner Responsibilities

The capability planner must:

1. Parse the project-owned GraphQL request.
2. Resolve the top-level field to a capability id.
3. Validate required arguments and operation type.
4. Consult the capability registry for:
   - supported auth families
   - preferred transport
   - fallback transport
   - read/write classification
   - implementation status
5. Execute the reviewed adapter path only if the capability is implemented.

Planner implementation rule:

- Keep the public-field registry separate from the capability-route planner.
- The public-field registry owns request parsing, argument mapping, and response shaping.
- The capability-route planner owns auth selection, preferred transport choice, and fallback decisions.
- Public field definitions must stay mechanically aligned with capability metadata such as `publicOperationName`; drift between those registries is an internal design bug.
- Alignment is bidirectional: every public field must reference an implemented stable capability, and every implemented stable capability with a `publicOperationName` must have a matching public field registration.
- After planning resolves to a stable capability id, execution must reuse the same internal capability executor used by direct SDK/CLI helpers so the public GraphQL surface cannot drift from the stable capability surface.
- Reviewed routes must be declared in explicit planner metadata so mixed-auth behavior is visible in one place rather than hidden in per-capability branching.
- The raw GraphQL transport path must not be reused implicitly by the public contract planner.
- The low-level raw GraphQL requester should live in a separate module from the public-contract planner so escape-hatch transport logic cannot silently leak into stable request planning.

## Initial Parsing Scope

The first implementation slice may keep the parser intentionally small:

- one top-level field per request
- string, integer, boolean, and null argument literals
- selection sets used only for response projection
- no variables, fragments, aliases, or directives yet

These limits are acceptable as long as diagnostics are explicit and the contract remains project-owned.

## Response Shaping

- `accountMe` returns a projected account object.
- `post(id)` returns a projected post object plus `referencedPosts` when requested.
- Mutations return stable project-defined objects, not raw transport payloads.
- Projection is applied after capability execution so callers receive only the requested stable fields.

## Explicit Non-Goals For This Slice

- full GraphQL spec compliance
- passthrough of arbitrary user GraphQL to X
- auto-support for all deferred capability families
- claims that `likedPosts` is live before a reviewed adapter exists

## References

- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`
- `design-docs/specs/design-api-inventory.md`
