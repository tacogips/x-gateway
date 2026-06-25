# x-gateway

AI-oriented command-line and Swift library gateway for X API operations.

The Swift package exposes two executable products:

- `x-gateway-reader`: read-only command surface for account, post, search, timeline, and usage queries
- `x-gateway-writer`: write command surface for posting, replies, quotes, reposts, unreposts, and deletions

It also exposes the `XGatewayCore` Swift library:

```swift
import XGatewayCore
```

## Development

```bash
nix develop
task build
task test
swift run x-gateway-reader -- help
swift run x-gateway-writer -- help
```

The package uses Swift Package Manager with:

- Library target: `XGatewayCore`
- Read executable target: `XGatewayRead`
- Write executable target: `XGatewayWrite`
- Installed executables: `x-gateway-reader`, `x-gateway-writer`

Build or install each command independently:

```bash
swift build -c release --product x-gateway-reader
swift build -c release --product x-gateway-writer
```

```bash
task install-reader PREFIX="$HOME/.local"
task install-writer PREFIX="$HOME/.local"
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

Use `x-gateway-reader graphql query` for reviewed read operations:

```bash
x-gateway-reader graphql query 'query { accountMe { id username name } }' --json
```

```bash
x-gateway-reader graphql query 'query { followingTimeline(maxResults: 10, maxUsers: 25, maxResultsPerUser: 5) { posts { id text createdAt author { username name } metrics { impressionCount likeCount replyCount repostCount quoteCount bookmarkCount } } pageInfo { resultCount newestId oldestId nextToken } } }' --json
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

Use `x-gateway-writer graphql query` for reviewed write operations:

```bash
x-gateway-writer graphql query 'mutation { createPost(text: "hello") { id text } }' --json
```

```bash
x-gateway-writer graphql query 'mutation { replyToPost(text: "reply", replyToPostId: "123") { id text } }' --json
```

The write executable rejects read queries, and the read executable rejects
mutations. Use `graphql schema` on either executable to inspect the project-owned
schema.

## Homebrew Formula

Build local formula archives. The archive contains both command binaries:

```bash
task build:homebrew -- darwin-arm64 darwin-x64
```

Render formulae after both platform archives exist:

```bash
task homebrew:formula-reader -- 0.1.3
task homebrew:formula-writer -- 0.1.3
```

Render directly into the default sibling tap checkout:

```bash
task homebrew:tap-formula-reader -- 0.1.3
task homebrew:tap-formula-writer -- 0.1.3
```

Install from the tap after the formula is published:

```bash
brew tap tacogips/homebrew-tap
brew install tacogips/homebrew-tap/x-gateway-reader
brew install tacogips/homebrew-tap/x-gateway-writer
```

## Nix

Install commands:

```bash
nix profile install github:tacogips/x-gateway#x-gateway-reader
nix profile install github:tacogips/x-gateway#x-gateway-writer
```

Run without installing:

```bash
nix run github:tacogips/x-gateway#x-gateway-reader -- version
nix run github:tacogips/x-gateway#x-gateway-writer -- version
```
