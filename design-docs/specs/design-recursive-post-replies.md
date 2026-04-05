# Recursive Post Replies Design

This document defines the canonical recursive reply expansion path through `Post.replies(...)` in the project-owned GraphQL contract.

## Overview

The stable contract exposes direct-reply lookup through a nested field on `Post`:

```graphql
query {
  post(id: "123") {
    id
    replies(maxResults: 10) {
      posts {
        id
        replies(maxResults: 10) {
          posts { id }
          pageInfo { resultCount }
        }
      }
      pageInfo { resultCount }
    }
  }
}
```

The replies payload remains `PostPage`, so recursion works through `PostPage.posts: [Post!]!`.

## Semantics

- `Post.replies(...)` returns direct replies to the current post object.
- Direct replies are implemented through the reviewed `post.replies` capability and the REST v2 recent-search operator `in_reply_to_tweet_id:<postId>`.
- `Post.replies(...)` is the canonical public GraphQL surface for reply traversal.

## Execution Model

The public GraphQL contract still supports exactly one top-level field per request. The implementation now adds a bounded nested-execution pass after the top-level stable capability resolves:

1. Parse one top-level public GraphQL field.
2. Execute the reviewed top-level stable capability.
3. Walk the requested selection tree.
4. When a selected field is `Post.replies(...)`, execute the stable `post.replies` capability using the parent post id.
5. Recurse into the returned `PostPage.posts` selections.
6. Project the final hydrated stable payload.

This is intentionally limited. The repository is not moving to general GraphQL resolver execution for arbitrary nested fields in this slice.

## Parser and Validation Changes

- Nested field arguments are now supported for reviewed child fields.
- The parser still rejects:
  - variables
  - fragments
  - aliases
  - directives
  - multi-top-level-field documents
- Validation remains schema-driven. Unsupported nested fields or nested arguments fail explicitly.

## Guardrails

Recursive reply expansion can create N+1 capability calls. This slice applies an explicit request-local budget:

- Maximum nested reply expansions per GraphQL request: `25`

If the request exceeds that budget, validation must fail with guidance to reduce nesting depth or `maxResults`.

## Non-Goals

- General nested capability execution for arbitrary public GraphQL fields
- Automatic batching or dataloader-style consolidation across reply lookups
- Full conversation-tree assembly beyond explicit recursive `replies(...)` selections

## References

- `design-docs/specs/design-public-graphql-contract.md`
- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`
