# Post Metrics Design

This document defines stable post metrics exposure for the project-owned GraphQL contract.

## Overview

The stable contract already returns post identity, text, media, references, and reply traversal. This slice adds post metrics as a stable nested object:

```graphql
query {
  post(id: "123") {
    id
    metrics {
      likeCount
      replyCount
      repostCount
      quoteCount
      bookmarkCount
      impressionCount
    }
  }
}
```

## Stable Shape

```graphql
type PostMetrics {
  likeCount: Int
  replyCount: Int
  repostCount: Int
  quoteCount: Int
  bookmarkCount: Int
  impressionCount: Int
}
```

```graphql
type Post {
  ...
  metrics: PostMetrics!
}
```

The same metrics object is reused across `Post`, `ReferencedPost`, and `ReferencedPostLevel2`.

## Nullability Rules

- The `metrics` object itself is always present in the stable payload.
- Each metric field is nullable.
- If the X API plan, auth scope, token context, or endpoint payload omits a metric, that field returns `null`.
- Missing metrics must not fail a successful post read.

## Source Mapping

- `likeCount`, `replyCount`, `repostCount`, `quoteCount`, and `bookmarkCount` come from upstream public metrics when available.
- `impressionCount` prefers the first reviewed numeric source available.
- Other-user timeline reads, including followed-account reads inside `followingTimeline`, must not request owner-only metric field groups solely to populate `impressionCount`; when no public impression source is returned, `impressionCount` remains `null`.
- Owner-only metric groups such as `organic_metrics` and `promoted_metrics` may be considered only for a reviewed self-owned read path where the authenticated user is allowed to access them.

## Capability Impact

No new capability id is introduced.

- `post.get` returns a richer post payload.
- `post.replies` returns richer reply-page items.
- timeline/search payloads inherit the richer post shape.

## Non-Goals

- Additional upstream calls just to backfill missing metrics
- Hard failures when only some metrics are unavailable
- Separate metric-specific auth probing

## References

- `design-docs/specs/design-public-graphql-contract.md`
- `design-docs/specs/architecture.md`
- `design-docs/specs/command.md`
