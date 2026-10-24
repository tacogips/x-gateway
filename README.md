# x-gateway

After `auth oauth2 --store kinko`, refresh `X_GW_TOKEN` from kinko in the calling
environment: login cannot replace existing shell values. Remove stale `--token`
overrides. Depending on the operation, complete OAuth1 credentials or
`X_GW_APP_TOKEN` may select a different grant. Login output explains this selection,
and GraphQL authentication errors identify the source actually used.

AI-oriented command-line and Swift library gateway for X API operations.

The Swift package exposes two executable products:

- `x-gateway-reader`: read-only command surface for account, user, post, engagement, search, news, trends, timeline, bookmark, count, and usage queries
- `x-gateway-writer`: write command surface for posting, replies, quotes, reposts, unreposts, bookmarks, Articles, and deletions

It also exposes the `XGatewayCore` Swift library:

```swift
import XGatewayCore
```

Embedding runtimes can reuse author metadata with the optional user-metadata
exchange. Supply a JSON array of `{id, username, name}` through
`X_GW_USER_MEMORY_JSON`, or bounded parts named `X_GW_USER_MEMORY_JSON_0`, etc.
with `X_GW_USER_MEMORY_PARTS`. Post reads omit author expansions, restore known
users locally, and look up only missing IDs in groups of at most 100. Successful
additions are returned in GraphQL `extensions.userMemory`; the SDK writes no
files. The runtime merges these additions into its separate user cache and owns TTL/LRU policy. The exchange
is bounded to 10,000 users and 800 KB; capacity or optional lookup failures leave
posts readable and increment `userMemoryUnavailableCount`. Names remain as last
recorded until the embedding runtime expires or refreshes the cached profile.

Optional GraphQL string arguments accept `null` as omission, including the first
page's `nextToken`. Post-page responses include `pageInfo.nextToken: null` at the
end of a scan, including empty pages, so declarative workflows can distinguish
completion without a script.

## Development

```bash
mise install
mise run build
mise run test
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
mise run install-reader PREFIX="$HOME/.local"
mise run install-writer PREFIX="$HOME/.local"
```

Swift smoke tests run through an executable harness:

```bash
mise run test
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

The Swift GraphQL surface also includes OpenAPI-backed parity fields that are
not naturally represented by the higher-level post/social objects. These return
`OpenAPIResult { ok payload }` and cover compliance jobs, Communities, Community
Notes, all-time counts, analytics, insights, finite filtered-stream rule
counts, media lookup/upload
initialization/finalization/metadata, personalized trends, public keys,
affiliates, reposts-of-me, webhooks, activity subscriptions, account-activity
subscriptions, OpenAPI spec lookup, post repost object reads, user public-key
registration, raw encrypted Chat conversation primitives, media one-shot
upload/append, Chat media upload append/finalize, and Chat/DM media
download-to-file helpers. Long-running stream consumption is exposed through
the separate bounded `stream` command rather than through GraphQL.
Spaces lookup/search fields return typed `SpacePage`/`Space` objects; Space
buyers and posts use the existing typed `UserPage` and `PostPage` surfaces.
Filtered-stream rule reads and updates return typed `StreamRulePage` and
`StreamRuleUpdateResult` objects.

Nested `Post.replies(...)` selections are hydrated through bounded recent-search
reply lookups and are exposed in capability metadata as `post.replies`.

Swift signs supported non-usage live requests with OAuth1 when complete OAuth1
credentials are configured and otherwise falls back to a bearer token. `apiUsage`,
search/news/trends, and bookmark operations remain bearer-token only because the
current X API endpoints require OAuth2 user context. Attachment-backed
`createPost`, `replyToPost`, and `quotePost` mutations prefer OAuth2 bearer
credentials with `media.write`, fall back to OAuth1 when no bearer token is
configured, validate `image`, `gif`, and `video` attachment file extensions,
media mix limits, and local file size limits before upload, upload attachments
through the X media upload API, apply alt text for image/GIF attachments when
provided, and post with `media.media_ids`. Direct Message mutations also accept
the same local `attachments` input and upload files as DM media with OAuth2
`media.write` before sending `attachments { media_id }` to X.

HTTP errors expose optional finite `providerProblem` and `providerReason` values,
plus an integer `providerErrorCode` bounded to 0...99999. These fields contain
only recognized machine values; unknown provider strings become `unknown`.
Callers with a private data boundary should allowlist these fields and exclude
free-form `details`, `summary`, messages, resource identifiers and URLs.

Ordinary post reads request public metrics only, including liked posts, lists,
searches, timelines and single/batch lookups. Private organic/promoted metrics
are not requested implicitly because X restricts them to eligible owned posts
created within the last 30 days. Public historical reads have no SDK-imposed
30-day cutoff; availability still depends on the upstream endpoint.

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

- `X_GW_TOKEN`: OAuth2 user-context bearer token for user/private endpoints
- `X_GW_APP_TOKEN`: app-only bearer token for public app-context endpoints
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

Check configuration completeness, OAuth2 expiry metadata, and credential status
without printing any secret values:

```bash
x-gateway-reader doctor
x-gateway-writer doctor --json --pretty
```

`doctor` performs read-only requests to X for each configured credential family.
Use `--online false` to inspect only local environment and expiry configuration.

OAuth1 credentials are required for OAuth1-backed posting and attachment upload.
OAuth2 user-context bearer credentials are required for user/private endpoints
such as bookmarks, search users/news/trends, usage, Lists, DMs, likes, mutes,
blocks, OpenAPI parity user operations, and other user-context social
mutations. App-only bearer credentials are preferred for public app-context
endpoints such as full-archive search, tweet counts, stream rules, and the
OpenAPI spec. `--token` remains an explicit override for either token family.

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
x-gateway-writer graphql query 'mutation { createDirectMessage(participantId: "123", text: "hello", attachments: [{ kind: "gif", filePath: "./image.gif" }]) { id eventType conversationId attachmentMediaKeys } }' --json
```

```bash
x-gateway-writer graphql query 'mutation { createArticleDraft(title: "Release notes", text: "Draft body") { id title } }' --json
```

```bash
x-gateway-writer graphql query 'mutation { publishArticle(articleId: "123") { postId } }' --json
```

## Streaming

Use `x-gateway-reader stream sample` or `x-gateway-reader stream filtered` for
bounded stream sessions. These commands require bearer credentials and stop when
`--max-events` is reached or `--duration-seconds` expires. `--reconnect true`
allows retry-backed reconnects within that same bounded session. In normal
output mode, the reader executable writes each received event immediately as one
NDJSON line. With `--json`, it buffers events and returns a final JSON summary.

```bash
x-gateway-reader stream sample --max-events 10 --duration-seconds 30 --json
```

```bash
x-gateway-reader stream filtered --max-events 10 --duration-seconds 30 --reconnect true --json
```

The write executable rejects read queries, and the read executable rejects
mutations. Use `graphql schema` on either executable to inspect the project-owned
schema.

## Homebrew Formula

Build local formula archives. The archive contains both command binaries:

```bash
mise run build:homebrew -- darwin-arm64 darwin-x64
```

Render formulae after both platform archives exist:

```bash
mise run homebrew:formula-reader -- 0.1.5
mise run homebrew:formula-writer -- 0.1.5
```

Render directly into the default sibling tap checkout:

```bash
mise run homebrew:tap-formula-reader -- 0.1.5
mise run homebrew:tap-formula-writer -- 0.1.5
```

Install from the tap after the formula is published:

```bash
brew tap tacogips/homebrew-tap
brew install tacogips/homebrew-tap/x-gateway-reader
brew install tacogips/homebrew-tap/x-gateway-writer
```

### Incremental recent search

`searchPosts` accepts optional `sinceId` and `nextToken` strings. These map to
X's recent-search `since_id` and `next_token` request parameters. For example:

```graphql
query {
  searchPosts(query: "from:example", maxResults: 100, sinceId: "123", downloadMedia: false) {
    posts { id text }
    pageInfo { nextToken newestId oldestId }
  }
}
```

Keep the same query and `sinceId` while following `pageInfo.nextToken`. Persist
the newest ID as the next run's watermark only after every page succeeds; keep
the previous watermark and page cursor if interrupted. Watermarks belong to the
caller's per-query state. Recent search retains X's recent-history window.

### Bounded home timeline reads

`homeTimeline` reads the authenticated account's reverse chronological home feed. It accepts optional `startTime`, `endTime`, `sinceId`, `untilId`, and `paginationToken`, matching the [X timeline endpoint](https://docs.x.com/x-api/users/get-timeline). Use RFC 3339 UTC date bounds and pass `pageInfo.nextToken` back as `paginationToken`, keeping the same bounds on every page. X enforces date/ID ordering and its timeline retention limits.

```graphql
{
  homeTimeline(maxResults: 100, startTime: "2026-10-16T15:00:00Z", endTime: "2026-10-17T15:00:00Z") {
    posts { id createdAt text }
    pageInfo { nextToken }
  }
}
```

### Liked post archive reads

`likedPosts` uses complete OAuth1 user credentials when available, including when a bearer token is also configured; bearer-only authentication remains supported. `Post` and `ReferencedPost` expose `references { id relation }` from upstream `referenced_tweets`, even when an expanded body is absent. Relations are `quoted`, `retweeted`, or `replied_to`. Consumers can perform bounded `posts(ids:)` hydration for missing references without mistaking absent expansions for absent relationships. The existing two-level body projection limit is unchanged.

HTTP failures include an optional numeric `error.httpStatus`; provider details remain separate so callers can retain bounded diagnostics without forwarding raw response text.

### Long post text and verified home timeline pagination

Post reads request `note_tweet` and expose its full nonblank text as `Post.text`,
including original posts and quoted references within the existing two-level
reference limit. Missing or malformed long-text fields fall back to ordinary
post text; no additional fetch is performed.

`homeTimeline(userId: "123", paginationToken: "...")` accepts an optional ASCII
numeric user ID already verified by the caller against `accountMe`. Supplying
that ID avoids the repeated `/2/users/me` lookup on each page. Omit it to retain
automatic account lookup. The timeline request still uses the same authenticated
credentials and X enforces access; this argument does not grant access to another
account. Pagination and date bounds are unchanged.

### Provider URL metadata

Post and both referenced-post levels expose `urlEntities { url expandedUrl displayUrl source }`.
The shared read request asks for `entities` alongside `note_tweet`; no extra API requests are made.
`source` is `entities` or `note_tweet.entities`, preserving where X supplied the metadata.
Original text is unchanged. Exact duplicate entries within each source are deduplicated.
Missing/malformed URL entities are omitted; invalid optional fields are absent. URL values must be
absolute HTTP(S), without credentials/whitespace/control characters and at most 8192 UTF-8 bytes;
display labels are control-free and at most 2048 bytes. These are untrusted provider metadata,
not verified destinations or permission to fetch. The gateway never follows t.co redirects.

Reference: https://docs.x.com/x-api/fundamentals/data-dictionary

Exact `posts(ids: ...)` reads can select `lookupAvailability { postId status reason }`.
The list has one entry per distinct requested ID in request order. Status is
`available`, `unavailable`, or `unknown`; reason is `returned`, `filtered`,
`missing`, `not-found`, `forbidden`, or `unknown`. Only a matching structured
provider error supports not-found/forbidden. Missing IDs without that evidence
remain unknown; no result proves permanent deletion. Provider error text is never
included, and the original posts are unchanged. Other `PostPage` operations return
null for this field (not evaluated). No additional provider request is made.

### Declared media and reference coverage

Post, ReferencedPost and ReferencedPostLevel2 expose additive `mediaAvailability`,
`mediaCoverageComplete`, `referenceAvailability` and `referenceCoverageComplete` fields.
Availability describes only identifiers declared in the provider response. `available`
means their metadata was projected, not that image bytes were downloaded or inspected.
Empty declarations can be complete for this narrow scope; this does not attest that a
post has no visual content. Malformed or oversized declarations remain incomplete.

Unresolved entries use `unknown` with `missing`, `unsupported`, `filtered` or
`depth-limit`; none proves deletion or permanent unavailability. Quoted media omitted
from expansions and references beyond the two-level projection are explicit gaps.
Callers may resolve those gaps using their own bounded, account-bound exact-ID lookup
budget and cache. The SDK performs no additional requests automatically. Original
post text, including available note_tweet full text, is unchanged.

The shared request includes the documented `variants` media field so video/GIF
metadata can retain a usable source. It does not add undocumented nested expansion
values to the exact-ID endpoint. See the [official lookup field reference](https://docs.x.com/x-api/posts/get-posts-by-ids).

### Failed-request retry diagnostics

Instrumented JSON errors include `requestAttempts`, `retryAttempts`, `backoffMs`, and
`retryStopReason` alongside `httpStatus` and `retryable`. Counts and cumulative
sleep milliseconds describe the failed HTTP request, including its automatic
retries, rather than all requests in a compound operation. `not-started` means
failure occurred before the retry-managed HTTP transport was entered;
`non-retryable`, `retry-disabled`, `method-not-retryable`, and `retry-exhausted`
explain why it stopped. These fields contain no URLs, credentials, or content.
Errors outside this instrumented boundary omit counts rather than inventing zero attempts.
Successful responses retain their existing format and do not report HTTP counts.

### Resource observations

GraphQL success `extensions.resourceUsage` and errors `error.resourceUsage` report bounded upstream HTTP response observations, before projection and user-cache restoration. They include returned post/user/media identifiers as SHA-256 hashes with UTC response days, successful response counts, and unclassified/unknown observations. Raw IDs, text, tokens and request URLs are excluded. Cached author restoration does not count as a new upstream user read. These are not billed units or an invoice: provider deduplication, owned-read discounts, adjustments, transport uncertainty and unclassified resources remain distinct.
