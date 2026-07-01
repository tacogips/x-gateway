# x-gateway

AI-oriented command-line and Swift library gateway for X API operations.

The Swift package exposes two executable products:

- `x-gateway-reader`: read-only command surface for account, user, post, engagement, search, news, trends, timeline, bookmark, count, and usage queries
- `x-gateway-writer`: write command surface for posting, replies, quotes, reposts, unreposts, bookmarks, Articles, and deletions

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
project-owned GraphQL fields: `accountMe`, `apiUsage`, `user`,
`userByUsername`, `followers`, `following`, `post`, `postLikingUsers`, `postRepostingUsers`,
`postQuotes`, `searchAllPosts`, `searchUsers`, `searchNews`, `news`,
`trendsByWoeid`, `recentPostCounts`, `bookmarks`, `bookmarkFolders`,
`bookmarksByFolder`, `searchPosts`, `homeTimeline`, `followingTimeline`,
`userTimeline`, `mentionsTimeline`, `createPost`, `deletePost`, `replyToPost`,
`quotePost`, `repostPost`, `unrepostPost`, `bookmarkPost`, `removeBookmark`,
`createArticleDraft`, and `publishArticle`.

The Swift GraphQL surface also includes OpenAPI-backed parity fields for
non-Spaces, non-streaming X API families that are not naturally represented by
the higher-level post/social objects. These return `OpenAPIResult { ok payload }`
and cover compliance jobs, Communities, Community Notes, all-time counts,
analytics, insights, media lookup/upload initialization/finalization/metadata,
personalized trends, public keys, affiliates, reposts-of-me, webhooks, activity
subscriptions, account-activity subscriptions, OpenAPI spec lookup, post repost
object reads, user public-key registration, raw encrypted Chat conversation
primitives, media one-shot upload/append, Chat media upload append/finalize, and
Chat/DM media download-to-file helpers. Spaces, stream links, and stream
connection management remain intentionally outside this GraphQL slice.

Nested `Post.replies(...)` selections are hydrated through bounded recent-search
reply lookups and are exposed in capability metadata as `post.replies`.

Swift signs supported non-usage live requests with OAuth1 when complete OAuth1
credentials are configured and otherwise falls back to a bearer token. `apiUsage`,
search/news/trends, and bookmark operations remain bearer-token only because the
current X API endpoints require OAuth2 user context. Attachment-backed
`createPost`, `replyToPost`, and `quotePost` mutations prefer OAuth2 bearer
credentials with `media.write`, fall back to OAuth1 when no bearer token is
configured, upload image attachments through the X media upload API, apply alt
text when provided, and post with `media.media_ids`. Direct Message mutations
also accept the same local `attachments` input and upload files as DM media with
OAuth2 `media.write` before sending `attachments { media_id }` to X.

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
- `X_GW_OAUTH2_CLIENT_ID`
- `X_GW_OAUTH2_CLIENT_SECRET`
- `X_GW_OAUTH2_REDIRECT_URI` (defaults to `http://127.0.0.1:8765/callback`)
- `X_GW_OAUTH2_SCOPES` (defaults to all known X OAuth2 scopes, including
  `media.write` for media upload)

OAuth1 credentials are required for OAuth1-backed posting and attachment upload.
OAuth2 bearer credentials are required for bearer-only endpoints such as
bookmarks, search/news/trends, usage, Lists, DMs, likes, mutes, blocks,
OpenAPI parity operations, and other user-context social mutations.

Generate an OAuth2 bearer token with the built-in loopback callback server:

```bash
x-gateway-reader auth oauth2 --client-id "$X_GW_OAUTH2_CLIENT_ID" --store kinko --json
```

Register the same callback URI in the X app settings, for example
`http://127.0.0.1:8765/callback`. The command opens the X authorization page,
waits for the local callback, exchanges the authorization code with PKCE, and
stores `X_GW_OAUTH2_CLIENT_ID`, optional `X_GW_OAUTH2_CLIENT_SECRET`,
`X_GW_TOKEN`, `X_GW_OAUTH2_REFRESH_TOKEN`, `X_GW_OAUTH2_SCOPE`, and
`X_GW_OAUTH2_EXPIRES_AT` in kinko when returned. Token values are not printed.
When `--open-browser false` is used, the authorization URL is written to stderr
before the command waits for the loopback callback.

## Read-Only GraphQL

Use `x-gateway-reader graphql query` for reviewed read operations:

```bash
x-gateway-reader graphql query 'query { accountMe { id username name } }' --json
```

```bash
x-gateway-reader graphql query 'query { userByUsername(username: "xdev") { id username name } }' --json
```

```bash
x-gateway-reader graphql query 'query { usersByUsernames(usernames: ["xdev", "twitterdev"]) { users { id username name } pageInfo { resultCount } } }' --json
```

```bash
x-gateway-reader graphql query 'query { posts(ids: ["123"]) { posts { id text author { username } } pageInfo { resultCount } } }' --json
```

```bash
x-gateway-reader graphql query 'query { followers(userId: "1955249782982848512", maxResults: 5) { users { id username name } pageInfo { resultCount nextToken } } }' --json
```

```bash
x-gateway-reader graphql query 'query { following(userId: "1955249782982848512", maxResults: 5) { users { id username name } pageInfo { resultCount nextToken } } }' --json
```

```bash
x-gateway-reader graphql query 'query { postQuotes(postId: "123", maxResults: 10) { posts { id text author { username } } pageInfo { resultCount nextToken } } }' --json
```

```bash
x-gateway-reader graphql query 'query { recentPostCounts(query: "from:xdev", granularity: "day") { totalPostCount counts { start end postCount } pageInfo { nextToken } } }' --json
```

```bash
x-gateway-reader graphql query 'query { searchAllPosts(query: "from:xdev has:media", maxResults: 10) { posts { id text } pageInfo { resultCount nextToken } } }' --json
```

```bash
x-gateway-reader graphql query 'query { searchUsers(query: "xdev", maxResults: 10) { users { id username name } pageInfo { nextToken } } }' --json
```

```bash
x-gateway-reader graphql query 'query { searchNews(query: "technology") { stories { id name summary postIds } pageInfo { resultCount } } }' --json
```

```bash
x-gateway-reader graphql query 'query { trendsByWoeid(woeid: 1, maxTrends: 20) { trends { name postCount } } }' --json
```

```bash
x-gateway-reader graphql query 'query { bookmarks(maxResults: 10) { posts { id text } pageInfo { resultCount nextToken } } }' --json
```

```bash
x-gateway-reader graphql query 'query { bookmarkFolders(maxResults: 10) { folders { id name } pageInfo { nextToken } } }' --json
```

```bash
x-gateway-reader graphql query 'query { likedPosts(userId: "1955249782982848512", maxResults: 10) { posts { id text } pageInfo { resultCount nextToken } } }' --json
```

```bash
x-gateway-reader graphql query 'query { mutedUsers(userId: "1955249782982848512", maxResults: 10) { users { id username name } pageInfo { resultCount } } }' --json
```

```bash
x-gateway-reader graphql query 'query { ownedLists(userId: "1955249782982848512", maxResults: 10) { lists { id name private } pageInfo { resultCount } } }' --json
```

```bash
x-gateway-reader graphql query 'query { listPosts(listId: "123", maxResults: 10) { posts { id text } pageInfo { resultCount nextToken } } }' --json
```

```bash
x-gateway-reader graphql query 'query { dmEvents(maxResults: 10, eventTypes: ["MessageCreate"]) { events { id eventType conversationId senderId text } pageInfo { resultCount nextToken } } }' --json
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

```bash
x-gateway-writer graphql query 'mutation { bookmarkPost(postId: "123") { id bookmarked } }' --json
```

```bash
x-gateway-writer graphql query 'mutation { likePost(postId: "123") { id liked } }' --json
```

```bash
x-gateway-writer graphql query 'mutation { followUser(targetUserId: "123") { id following } }' --json
```

```bash
x-gateway-writer graphql query 'mutation { createList(name: "x-gateway", private: true) { id name } }' --json
```

```bash
x-gateway-writer graphql query 'mutation { updateList(listId: "123", description: "updated") { id updated } }' --json
```

```bash
x-gateway-writer graphql query 'mutation { createDirectMessage(participantId: "123", text: "hello", attachments: [{ kind: "image", filePath: "./image.gif" }]) { id eventType conversationId attachmentMediaKeys } }' --json
```

```bash
x-gateway-writer graphql query 'mutation { createArticleDraft(title: "Release notes", text: "Draft body") { id title } }' --json
```

```bash
x-gateway-writer graphql query 'mutation { publishArticle(articleId: "123") { postId } }' --json
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
