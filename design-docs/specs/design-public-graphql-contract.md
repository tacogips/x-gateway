# Public GraphQL Contract Design

This document defines the project-owned GraphQL-shaped request contract for `x-gateway`.

## Goal

Provide a stable GraphQL-shaped public contract that expresses user intent without exposing raw X web GraphQL transport details such as document ids, operation names, feature flags, or rollout toggles.

## Contract Rules

- This contract is owned by `x-gateway`, not by X web GraphQL.
- Top-level fields map to stable project capabilities.
- Transport selection is internal and decided by the capability planner.
- The canonical entrypoints are `graphql query '<query>'` in CLI and `createXGatewayClient().graphqlQuery({ query, traceId? })` in the SDK.
- The current public CLI and SDK do not expose a separate raw upstream GraphQL escape hatch.
- Unsupported project fields must fail with `UNSUPPORTED` or `VALIDATION_ERROR` without silently falling through to any upstream GraphQL transport.

## Initial Public Fields

### Query

- `accountMe`
  - maps to capability `account.me`
- `post(id: ID!)`
  - maps to capability `post.get`

### Mutation

- `createPost(text: String!, attachments: [PostAttachmentInput!])`
  - maps to capability `post.create`
- `deletePost(postId: ID!)`
  - maps to capability `post.delete`
- `replyToPost(text: String!, replyToPostId: ID!, attachments: [PostAttachmentInput!])`
  - maps to capability `post.reply`
- `quotePost(text: String!, quotedPostId: ID!, attachments: [PostAttachmentInput!])`
  - maps to capability `post.quote`
- `repostPost(postId: ID!)`
  - maps to capability `post.repost`
- `unrepostPost(postId: ID!)`
  - maps to capability `post.unrepost`

### Attachment Input

`PostAttachmentInput` is project-owned and intentionally smaller than upstream X media contracts.

- `kind: "image"` only in the current reviewed slice
- `filePath: String!`
- `altText: String`
- `attachments` may contain 1 to 4 items when provided
- unsupported media kinds or extra object fields must fail validation explicitly

Example canonical mutations:

```graphql
mutation {
  createPost(
    text: "hello"
    attachments: [{ kind: "image", filePath: "/tmp/a.png", altText: "example" }]
  ) {
    id
    text
  }
}
```

```graphql
mutation {
  replyToPost(
    text: "hello"
    replyToPostId: "123"
    attachments: [{ kind: "image", filePath: "/tmp/a.png" }]
  ) {
    id
    text
  }
}
```

```graphql
mutation {
  quotePost(
    text: "hello"
    quotedPostId: "123"
    attachments: [{ kind: "image", filePath: "/tmp/a.png" }]
  ) {
    id
    text
  }
}
```

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
- The public-contract planner must remain transport-agnostic and must not silently reintroduce an upstream GraphQL passthrough path as fallback behavior.

## Initial Parsing Scope

The first implementation slice may keep the parser intentionally small:

- one top-level field per request
- string, integer, boolean, null, list, and object argument literals
- selection sets used only for response projection
- no variables, fragments, aliases, or directives yet

These limits are acceptable as long as diagnostics are explicit and the contract remains project-owned.

## Validation and Migration Guidance

- Validation errors must name the unsupported public field or argument.
- Validation errors must also reject unsupported selection fields instead of silently ignoring them.
- Validation errors must reject unexpected arguments instead of silently accepting transport-shaped extras.
- Object-valued public fields must require a nested selection set, and scalar public fields must reject nested selections.
- When callers use superseded contract names from earlier iterations, errors should include the canonical replacement.
- Current migration guidance must explicitly cover:
  - `deletePost(id: ...)` -> `deletePost(postId: ...)`
  - `repostPost(id: ...)` -> `repostPost(postId: ...)`
  - `unrepostPost(id: ...)` -> `unrepostPost(postId: ...)`
- Stable liked-post lookup is currently deferred from the public GraphQL contract until a reviewed live adapter route is verified.
- Attachment validation must reject:
  - unknown attachment object fields
  - `kind` values other than `"image"`
  - empty `filePath`
  - empty `altText`
  - more than four attachments

## Response Shaping

- `accountMe` returns a projected account object.
- `post(id)` returns a projected post object plus `referencedPosts` when requested.
- Mutations return stable project-defined objects, not raw transport payloads.
- Projection is applied after capability execution so callers receive only the requested stable fields.
- Projection must also reject adapter payload drift when a field declared as scalar returns an object/list, or when a field declared as object/list returns an incompatible payload shape.

## Explicit Non-Goals For This Slice

- full GraphQL spec compliance
- passthrough of arbitrary user GraphQL to X
- auto-support for all deferred capability families
- claims that `likes` is part of the stable contract before a reviewed live adapter exists

## References

- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`
- `design-docs/specs/design-api-inventory.md`
