# Post Replies Query Design

This document is historical. The top-level `postReplies(...)` field described here is no longer part of the stable public GraphQL contract.

## Status

Superseded on 2026-04-05 by the canonical nested `Post.replies(...)` contract described in `design-docs/specs/design-recursive-post-replies.md`.

## Historical Overview

An earlier slice added a stable top-level query:

```graphql
query {
  postReplies(postId: "123", maxResults: 10) {
    posts { id text author { username } }
    pageInfo { resultCount nextToken }
  }
}
```

## Historical Rationale

Use a top-level `postReplies` field instead of `Post.replies(...)`.

Rationale:

- The current public GraphQL layer plans exactly one top-level reviewed capability per request.
- Nested selections are projection-only in the current architecture; they do not trigger additional capability execution.
- A child field on `Post` would require nested capability execution and would create N+1 search behavior for timeline queries in the current implementation model.
- A top-level field matches the existing `PostPage` pagination pattern already used by `searchPosts`, `homeTimeline`, `userTimeline`, and `mentionsTimeline`.

## Historical Semantics

- `postReplies(postId: ID!, ...)` returns direct replies to the referenced post, not the full conversation tree.
- Direct-reply semantics are implemented with the X recent-search operator `in_reply_to_tweet_id:<postId>`.
- The result shape reuses `PostPage`.
- `maxResults`, `paginationToken`, `mediaRootDir`, `downloadMedia`, `forceDownload`, and `includePromoted` behave the same way they do on existing page-returning query fields.

## Historical Capability Mapping

- Public GraphQL field: `postReplies`
- Stable capability id: `post.replies`
- Access type: read
- Transport strategy: REST v2 recent search
- Auth modes: OAuth1 or bearer, matching the reviewed recent-search baseline

## Historical Pagination and Limits

- `maxResults` is optional and follows the same validation envelope as the existing recent-search capability.
- `paginationToken` maps to the recent-search `next_token` request parameter.
- The stable contract continues to expose provider pagination tokens explicitly through `pageInfo`.

## Historical Error Behavior

- Missing or empty `postId` must fail validation explicitly.
- Reply lookup must not silently widen to full-thread search semantics.
- Unsupported fields or arguments must continue to fail through the public GraphQL validation path with canonical guidance.

## Historical Non-Goals

- Nested `Post.replies(...)` on this iteration
- Recursive thread traversal
- Conversation tree assembly
- Reply ranking beyond upstream recent-search ordering

## Replacement

Use:

```graphql
query {
  post(id: "123") {
    replies(maxResults: 10) {
      posts { id text }
      pageInfo { resultCount nextToken }
    }
  }
}
```

## References

- `design-docs/specs/design-public-graphql-contract.md`
- `design-docs/specs/design-recursive-post-replies.md`
- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`
- `design-docs/references/README.md`
