# Command

## Status

Draft

## Current CLI

```bash
x-gateway-reader [--help] [--version]
x-gateway-writer [--help] [--version]
```

## OAuth2 Authorization Helper

`x-gateway-reader auth oauth2` starts a local loopback callback server for X
OAuth2 authorization-code-with-PKCE login. The default redirect URI is
`http://127.0.0.1:8765/callback`; it must be registered exactly in the X app
settings.

```bash
x-gateway-reader auth oauth2 --client-id "$X_GW_OAUTH2_CLIENT_ID" --store kinko --json
```

Command behavior:

- `--client-id` or `X_GW_OAUTH2_CLIENT_ID` is required.
- `--client-secret` or `X_GW_OAUTH2_CLIENT_SECRET` is optional for public/native
  clients.
- `--redirect-uri` or `X_GW_OAUTH2_REDIRECT_URI` must be an explicit-port
  `http://127.0.0.1/...` or `http://localhost/...` URL.
- `--scopes` or `X_GW_OAUTH2_SCOPES` accepts comma or whitespace-separated
  scopes; missing or `all` requests all known X OAuth2 scopes.
- `--store kinko` saves `X_GW_OAUTH2_CLIENT_ID`, optional
  `X_GW_OAUTH2_CLIENT_SECRET`, `X_GW_TOKEN`, `X_GW_OAUTH2_REFRESH_TOKEN`,
  `X_GW_OAUTH2_SCOPE`, and `X_GW_OAUTH2_EXPIRES_AT` when returned.
- `--open-browser false` must write the authorization URL to stderr before
  waiting so manual and headless flows can complete without corrupting JSON
  stdout.
- Access and refresh token values must never be printed in command output.

## Project-Owned GraphQL Contract

Stable read behavior is exposed through `x-gateway-reader graphql query
'<query>' --json`. The command accepts project-owned GraphQL fields and maps
them through reviewed capabilities instead of exposing raw X web GraphQL
transport details.

## Codex Reference And Cursor CLI Mapping

Step 2 design work records Codex-agent process behavior only as a reference for
future adapter design. It does not add agent-runner commands to the
`x-gateway-reader` or `x-gateway-writer` public surface.

Issue reference: Step 1 intake for Codex-agent reference behavior and Cursor CLI
reasoning-effort mapping in `codex-design-and-implement-review-loop`
issue-resolution mode.

Reference behavior from `../codex-agent`:

- `configOverrides` is a typed request option accepted by the SDK/session layer.
- New-session execution forwards each override to Codex CLI as `-c <override>`.
- Resume execution forwards the same overrides to `codex exec resume --json`,
  preserving one request option across both modes.
- The concrete reasoning-effort example is
  `model_reasoning_effort="high"`.
- The requested default reference path `../../codex-agent` is absent from this
  repository root; Step 1 established `../codex-agent` as the local reference
  root for this checkout.

Cursor behavior mapping rules:

- `x-gateway` must expose no raw Cursor CLI flags at the public GraphQL layer.
- Public callers express reasoning effort as project-owned request metadata, not
  as `-c`, Cursor argv, or any other provider-specific flag.
- A future Cursor adapter may translate that same project-owned reasoning-effort
  metadata to Cursor-specific argv only inside the Cursor adapter.
- Cursor adapter validation must run before subprocess launch, after stable
  request parsing and before provider-specific argv construction.
- Unsupported Cursor values must fail before process launch with an explicit
  validation diagnostic.
- If Cursor cannot apply a setting on resume while Codex can, that divergence
  must be intentional, documented, and surfaced in the adapter capability
  metadata rather than silently ignored.
- Adapter capability metadata must distinguish `newSession`, `resumeSession`,
  supported reasoning-effort values, and the unsupported-setting diagnostic.
- No public `x-gateway-reader` or `x-gateway-writer` command is added by this
  design update.
- Future Cursor CLI flags, environment variables, or resume-only limitations are
  adapter-private details and must not appear as public command flags unless a
  separate design explicitly promotes them to stable `x-gateway` metadata.

Reference verification commands for the Codex behavior are run from the
`x-gateway` repository root:

```bash
(cd ../codex-agent && bun test src/process/manager.test.ts src/sdk/agent-runner.test.ts src/sdk/agent-runner.process-options.test.ts)
(cd ../codex-agent && bun run typecheck)
```

The current MCP-parity read fields include:

- `user(id: ID!)` and `userByUsername(username: String!)`
- `users(ids: [ID!]!)` and `usersByUsernames(usernames: [String!]!)`
- `followers(userId: ID!, maxResults: Int, paginationToken: String)`
- `following(userId: ID!, maxResults: Int, paginationToken: String)`
- `posts(ids: [ID!]!, ...)`
- `likedPosts(userId: ID!, maxResults: Int, paginationToken: String, ...)`
- `postLikingUsers(postId: ID!, maxResults: Int, paginationToken: String)`
- `postRepostingUsers(postId: ID!, maxResults: Int, paginationToken: String)`
- `postQuotes(postId: ID!, maxResults: Int, paginationToken: String, ...)`
- `searchAllPosts(query: String!, maxResults: Int, ...)`
- `searchUsers(query: String!, maxResults: Int, nextToken: String)`
- `searchNews(query: String!, maxResults: Int, maxAgeHours: Int)`
- `news(id: ID!)`
- `trendsByWoeid(woeid: Int!, maxTrends: Int)`
- `recentPostCounts(query: String!, granularity: String, ...)`
- `bookmarks(maxResults: Int, paginationToken: String, ...)`
- `bookmarkFolders(maxResults: Int, paginationToken: String)`
- `bookmarksByFolder(folderId: ID!, ...)`
- `mutedUsers(userId: ID!, maxResults: Int, paginationToken: String)`
- `blockedUsers(userId: ID!, maxResults: Int, paginationToken: String)`
- `list(id: ID!)`, `ownedLists(...)`, `followedLists(...)`,
  `listMemberships(...)`, `pinnedLists(userId: ID!)`, `listFollowers(...)`,
  `listMembers(...)`, and `listPosts(...)`
- `dmEvents(...)`, `dmEvent(id:)`, `dmConversationEvents(...)`, and
  `dmConversationEventsById(...)`
- OpenAPI parity reads returning `OpenAPIResult`: `complianceJobs`,
  `complianceJob`, `communitiesSearch`, `community`, Community Notes reads,
  `allPostCounts`, `postAnalytics`, `postReposts`, `media`, `mediaByKey`,
  `mediaAnalytics`, `mediaUploadStatus`, insights reads, personalized trends,
  public keys, affiliates, reposts-of-me, OpenAPI spec lookup, webhooks,
  activity/account-activity subscriptions, and raw Chat conversation/event
  reads, finite filtered-stream rule counts, plus Chat and DM media
  download-to-file helpers. Spaces lookup/search fields return `SpacePage` or
  `Space`, and Space buyers/posts return `UserPage` and `PostPage`.
  Filtered-stream rule reads and updates return `StreamRulePage` and
  `StreamRuleUpdateResult`.
  Long-running stream connection consumption is handled by the separate
  `stream` command, not by short-lived GraphQL queries.

The current MCP-parity write mutations include:

- `bookmarkPost(postId: ID!)`
- `removeBookmark(postId: ID!)`
- `likePost(postId: ID!)` and `unlikePost(postId: ID!)`
- `followUser(targetUserId: ID!)` and `unfollowUser(targetUserId: ID!)`
- `muteUser(targetUserId: ID!)` and `unmuteUser(targetUserId: ID!)`
- `createList(...)`, `updateList(...)`, `deleteList(...)`, list member
  add/remove, list follow/unfollow, and list pin/unpin mutations
- `createDirectMessage(...)`, `createDirectMessageInConversation(...)`,
  `createDirectMessageConversation(...)`, and `deleteDirectMessage(...)`
- `createArticleDraft(title: String!, text: String, contentStateJSON: String)`
- `publishArticle(articleId: ID!)`
- OpenAPI parity mutations returning `OpenAPIResult`: compliance job creation,
  Community Notes create/delete/evaluate, reply hiding, DM block/unblock, media
  upload initialize/finalize plus metadata/subtitles, user public-key
  registration, webhooks, activity and account-activity subscriptions, raw
  encrypted Chat primitives, media one-shot upload/append, and Chat media upload
  initialization/append/finalization. Filtered-stream rule updates return
  `StreamRuleUpdateResult`.

Example post engagement reads:

```bash
x-gateway-reader graphql query 'query { followers(userId: "1955249782982848512", maxResults: 5) { users { id username name } pageInfo { resultCount nextToken } } }' --json
```

```bash
x-gateway-reader graphql query 'query { following(userId: "1955249782982848512", maxResults: 5) { users { id username name } pageInfo { resultCount nextToken } } }' --json
```

```bash
x-gateway-reader graphql query 'query { postLikingUsers(postId: "123", maxResults: 10) { users { id username name } pageInfo { resultCount nextToken } } }' --json
```

```bash
x-gateway-reader graphql query 'query { postQuotes(postId: "123", maxResults: 10) { posts { id text author { username } } pageInfo { resultCount nextToken } } }' --json
```

Example bookmark mutation:

```bash
x-gateway-writer graphql query 'mutation { bookmarkPost(postId: "123") { id bookmarked } }' --json
```

Example List and DM mutations:

```bash
x-gateway-writer graphql query 'mutation { createList(name: "x-gateway", private: true) { id name } }' --json
```

```bash
x-gateway-writer graphql query 'mutation { updateList(listId: "123", description: "updated") { id updated } }' --json
```

```bash
x-gateway-writer graphql query 'mutation { createDirectMessage(participantId: "123", text: "hello") { id eventType conversationId } }' --json
```

Example news and trends reads:

```bash
x-gateway-reader graphql query 'query { searchNews(query: "technology") { stories { id name summary postIds } pageInfo { resultCount } } }' --json
```

```bash
x-gateway-reader graphql query 'query { trendsByWoeid(woeid: 1) { trends { name postCount } } }' --json
```

Example Article writes:

```bash
x-gateway-writer graphql query 'mutation { createArticleDraft(title: "Release notes", text: "Draft body") { id title } }' --json
```

```bash
x-gateway-writer graphql query 'mutation { createArticleDraft(title: "Release notes", contentStateJSON: "{\"blocks\":[{\"key\":\"a\",\"text\":\"Bold\",\"type\":\"unstyled\",\"inline_style_ranges\":[{\"offset\":0,\"length\":4,\"style\":\"BOLD\"}],\"entity_ranges\":[],\"data\":{}}],\"entities\":[]}") { id title } }' --json
```

Example Spaces and finite stream-rule operations:

```bash
x-gateway-reader graphql query 'query { searchSpaces(query: "swift", state: "live", maxResults: 10) { spaces { id title state creatorId hostIds speakerIds } pageInfo { resultCount nextToken } } }' --json
```

```bash
x-gateway-reader graphql query 'query { streamRules(maxResults: 10) { rules { id value tag } pageInfo { resultCount nextToken } } }' --json
```

```bash
x-gateway-writer graphql query 'mutation { updateStreamRules(addJSON: "[{\"value\":\"from:xdev\",\"tag\":\"xdev\"}]") { rules { id value tag } summary { created valid } } }' --json
```

## Streaming Commands

`x-gateway-reader stream sample` and `x-gateway-reader stream filtered` open
bounded X stream sessions. They require bearer credentials and stop when
`--max-events` is reached or `--duration-seconds` expires. They are intentionally
read-command only and are rejected by `x-gateway-writer`. In normal output mode,
the reader executable writes each received event immediately as one NDJSON line;
with `--json`, it buffers events and returns one final JSON summary.

```bash
x-gateway-reader stream sample --max-events 10 --duration-seconds 30 --json
```

```bash
x-gateway-reader stream filtered --max-events 10 --duration-seconds 30 --reconnect true --json
```

`followingTimeline(...)` is the stable command surface for bounded followed
account aggregation:

```bash
x-gateway-reader graphql query 'query { followingTimeline(maxResults: 10, maxUsers: 25, maxResultsPerUser: 5) { posts { id text createdAt metrics { impressionCount likeCount replyCount repostCount quoteCount bookmarkCount } author { id username name } } pageInfo { resultCount newestId oldestId nextToken } } }' --json
```

Command behavior and validation:

- `followingTimeline(...)` maps only to capability `timeline.following`.
- `followers(...)` and `following(...)` return user lists from the X follow
  graph; `followingTimeline(...)` returns posts from followed users and must not
  be treated as a user-list replacement.
- `maxResults`, `maxUsers`, and `maxResultsPerUser` must be positive bounded
  values because the adapter fans out over followed-user timelines.
- `paginationToken` must not be used for `followingTimeline(...)` until a
  reviewed project-owned merged cursor exists.
- Followed-account fanout must request `public_metrics` and must not request
  `organic_metrics` or `promoted_metrics`.
- Missing owner-only metric access must surface as nullable metric fields,
  including `metrics.impressionCount: null`, rather than failing the command.
- Unsupported fields, arguments, or transport-shaped extras must fail with
  explicit validation or unsupported-capability diagnostics.
- `recentPostCounts.granularity` must be one of `minute`, `hour`, or `day`.
- `searchAllPosts.sortOrder` must be `recency` or `relevancy` when provided.
- `searchNews.maxResults` accepts 1...100 and `searchNews.maxAgeHours` accepts
  1...720.
- `searchUsers`, `searchNews`, `news`, `trendsByWoeid`, bookmark read/write
  operations, Lists, DMs, likes, mutes, and blocks require a user-context bearer
  token in the Swift transport slice because the current X endpoints require
  OAuth2 user context.
- `searchAllPosts`, tweet counts, stream rules, and `openAPISpec` prefer
  `X_GW_APP_TOKEN` app-only bearer credentials because those public endpoints
  reject OAuth2 user-context tokens. `--token` remains an explicit override.
- Bookmark reads use the reader command, bookmark mutations use the writer
  command, and both act on the authenticated user's bookmarks.
- DM writes can still fail with upstream 403 if the token, X app settings, or
  recipient account does not permit messages; x-gateway surfaces that as a
  permission error and does not fabricate a delete target.
- `pinnedLists(userId:)` is intentionally non-paged because the upstream
  `/2/users/{id}/pinned_lists` endpoint does not accept `max_results` or
  `pagination_token`.
