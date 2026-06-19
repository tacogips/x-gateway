# x-gateway

AI-oriented command-line and Swift library gateway for X API operations.

The Swift package exposes two executable products:

- `x-gateway-read`: read-only command surface for account, post, search, timeline, and usage queries
- `x-gateway-write`: write command surface for posting, replies, quotes, reposts, unreposts, and deletions

It also exposes the `XGatewayCore` Swift library:

```swift
import XGatewayCore
```

## Build

Build or install each command independently:

```bash
swift build -c release --product x-gateway-read
swift build -c release --product x-gateway-write
```

```bash
task install-read PREFIX="$HOME/.local"
task install-write PREFIX="$HOME/.local"
```

Swift smoke tests run through an executable harness:

```bash
task test
```

## Implemented Surface

The Swift implementation provides the CLI contract, structured error envelopes,
configuration/auth diagnostics, capability metadata, schema output, read/write
GraphQL operation separation, and live transport for the current top-level
project-owned GraphQL fields: `accountMe`, `apiUsage`, `post`, `searchPosts`,
`homeTimeline`, `followingTimeline`, `userTimeline`, `mentionsTimeline`,
`createPost`, `deletePost`, `replyToPost`, `quotePost`, `repostPost`, and
`unrepostPost`.

Nested `Post.replies(...)` selections are hydrated through bounded recent-search
reply lookups and are exposed in capability metadata as `post.replies`.

Swift signs non-usage live requests with OAuth1 when complete OAuth1 credentials
are configured and otherwise falls back to a bearer token. `apiUsage` remains
bearer-token only. Attachment-backed `createPost`, `replyToPost`, and
`quotePost` mutations require OAuth1, upload image attachments through the X
media upload API, apply alt text when provided, and post with `media.media_ids`.

Swift read projections include stable post metrics, authors, media asset URLs,
and referenced-post shortcuts when those expansions are present in X API
responses. Read projections honor `includePromoted`, filtering promoted posts by
default when upstream promotion metrics identify them. Read fields also honor
`mediaRootDir`, `downloadMedia`, and `forceDownload`: media files are
materialized under `mediaRootDir/<post-id>/`, existing files are reused unless
`forceDownload` is enabled, and `downloadMedia: false` keeps media source-only.

## Configuration

Configuration can come from environment variables or explicit CLI flags.

Common environment variables:

- `X_GW_TOKEN`: bearer token for bearer-compatible reads
- `X_GW_CONSUMER_KEY`
- `X_GW_CONSUMER_SECRET`
- `X_GW_ACCESS_TOKEN`
- `X_GW_ACCESS_TOKEN_SECRET`
- `X_GW_TIMEOUT_MS`
- `X_GW_RETRY`
- `X_GW_MEDIA_ROOT_DIR`

OAuth1 credentials are required for OAuth1-backed posting and attachment upload.

## Read-Only GraphQL

Use `x-gateway-read graphql query` for reviewed read operations:

```bash
x-gateway-read graphql query 'query { accountMe { id username name } }' --json
```

```bash
x-gateway-read graphql query 'query { followingTimeline(maxResults: 10, maxUsers: 25, maxResultsPerUser: 5) { posts { id text createdAt author { username name } metrics { impressionCount likeCount replyCount repostCount quoteCount bookmarkCount } } pageInfo { resultCount newestId oldestId nextToken } } }' --json
```

`followingTimeline(...)` is the stable field for fetching recent posts from
accounts followed by the authenticated user when `homeTimeline` is empty or
unavailable. It is a bounded project-owned aggregate over the authenticated
user's follow graph, not a raw X home timeline cursor.

For followed-account timeline fanout, `followingTimeline(...)` requests public
tweet fields only. It keeps `public_metrics`, does not request owner-only
`organic_metrics` or `promoted_metrics` for other users, and returns
`metrics.impressionCount` as `null` when no reviewed public impression source is
available.

Do not pass `followingTimeline.paginationToken` until x-gateway ships a reviewed
merged aggregate cursor. Current stable behavior is first-page bounded
aggregation with no upstream cursor passthrough.

## Write GraphQL

Use `x-gateway-write graphql query` for reviewed write operations:

```bash
x-gateway-write graphql query 'mutation { createPost(text: "hello") { id text } }' --json
```

```bash
x-gateway-write graphql query 'mutation { replyToPost(text: "reply", replyToPostId: "123") { id text } }' --json
```

The write executable rejects read queries, and the read executable rejects
mutations. Use `graphql schema` on either executable to inspect the project-owned
schema.

## Verification

Typical local verification commands:

```bash
swift build
swift run x-gateway-swift-smoke-tests
task ci
git diff --check
```
