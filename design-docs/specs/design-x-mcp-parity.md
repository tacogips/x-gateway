# X MCP Parity

## Status

Draft

## Evidence

Current official evidence was captured from `https://docs.x.com/tools/mcp.md`
on 2026-06-30. The X MCP page says the hosted X MCP server lets tools call X API
endpoints for search posts, user lookup, bookmarks, trends, news, Articles, and
more. Its capability table lists:

- Posts: fetch posts, see likers, reposters, quoters, and recent counts.
- Search: full-archive post search, user search, and news search.
- Users: resolve the current user, look up by id or handle, and read a user's
  posts, timeline, and mentions.
- Bookmarks: list, add, remove, and manage bookmark folders.
- News & Trends: get news stories and trends for a WOEID.
- Articles: create draft Articles and publish them.

Endpoint evidence was also checked against current X API reference markdown:

- `GET /2/users/{id}` from `https://docs.x.com/x-api/users/get-user-by-id.md`.
- `GET /2/users/by/username/{username}` from
  `https://docs.x.com/x-api/users/get-user-by-username.md`.
- `GET /2/tweets/{id}/liking_users` from
  `https://docs.x.com/x-api/posts/get-liking-users.md`.
- `GET /2/tweets/{id}/retweeted_by` from
  `https://docs.x.com/x-api/posts/get-reposted-by.md`.
- `GET /2/tweets/{id}/quote_tweets` from
  `https://docs.x.com/x-api/posts/get-quoted-posts.md`.
- `GET /2/tweets/counts/recent` from
  `https://docs.x.com/x-api/posts/get-count-of-recent-posts.md`.
- `GET /2/tweets/search/all` from
  `https://docs.x.com/x-api/posts/search-posts.md` and the current OpenAPI
  `/2/tweets/search/all` operation.
- `GET /2/users/search` from the current OpenAPI `/2/users/search` operation.
- `GET /2/news/search` from `https://api.x.com/2/openapi.json` current
  `/2/news/search` operation.
- `GET /2/news/{id}` from `https://api.x.com/2/openapi.json` current
  `/2/news/{id}` operation.
- `GET /2/trends/by/woeid/{woeid}` from the current OpenAPI
  `https://api.x.com/2/openapi.json` `/2/trends/by/woeid/{woeid}` operation.
- `GET /2/users/{id}/bookmarks` from
  `https://docs.x.com/x-api/bookmarks/get-bookmarks.md`.
- `POST /2/users/{id}/bookmarks` from
  `https://docs.x.com/x-api/bookmarks/create-bookmark.md`.
- `DELETE /2/users/{id}/bookmarks/{tweet_id}` from
  `https://docs.x.com/x-api/bookmarks/delete-bookmark.md`.
- `GET /2/users/{id}/bookmarks/folders` from
  `https://docs.x.com/x-api/bookmarks/get-bookmark-folders.md`.
- `GET /2/users/{id}/bookmarks/folders/{folder_id}` from
  `https://api.x.com/2/openapi.json` current
  `/2/users/{id}/bookmarks/folders/{folder_id}` operation.
- `POST /2/articles/draft` from `https://api.x.com/2/openapi.json` current
  `/2/articles/draft` operation.
- `POST /2/articles/{article_id}/publish` from
  `https://api.x.com/2/openapi.json` current
  `/2/articles/{article_id}/publish` operation.
- Batch lookup, liked posts, user follow/mute/block/list endpoints, Lists, and
  DMs from `https://api.x.com/2/openapi.json` as captured on 2026-06-30.

## Repository Inventory Before This Change

`x-gateway` already exposed:

- Read fields: `accountMe`, `apiUsage`, `post`, `searchPosts`, `homeTimeline`,
  `followingTimeline`, `userTimeline`, and `mentionsTimeline`.
- Nested read field: `Post.replies(...)`.
- Write mutations: `createPost`, `deletePost`, `replyToPost`, `quotePost`,
  `repostPost`, and `unrepostPost`.
- Read/write command split through `x-gateway-reader` and `x-gateway-writer`.
- Capability metadata, schema printing, argument validation, and live REST v2
  adapters behind a project-owned GraphQL contract.

## Implemented Parity Gaps

This slice implements the X MCP gaps that fit existing target boundaries and
stable GraphQL patterns:

- `user(id:)` maps to `GET /2/users/{id}`.
- `userByUsername(username:)` maps to `GET /2/users/by/username/{username}`.
- `users(ids:)` maps to `GET /2/users`.
- `usersByUsernames(usernames:)` maps to `GET /2/users/by`.
- `posts(ids:...)` maps to `GET /2/tweets`.
- `likedPosts(userId:maxResults:paginationToken:...)` maps to
  `GET /2/users/{id}/liked_tweets`.
- `postLikingUsers(postId:maxResults:paginationToken:)` maps to
  `GET /2/tweets/{id}/liking_users`.
- `postRepostingUsers(postId:maxResults:paginationToken:)` maps to
  `GET /2/tweets/{id}/retweeted_by`.
- `postQuotes(postId:maxResults:paginationToken:...)` maps to
  `GET /2/tweets/{id}/quote_tweets` and uses the existing `PostPage` projector.
- `searchAllPosts(query:...)` maps to `GET /2/tweets/search/all`.
- `searchUsers(query:maxResults:nextToken:)` maps to `GET /2/users/search`.
- `searchNews(query:maxResults:maxAgeHours:)` maps to `GET /2/news/search` and
  accepts current X API limits of `maxResults` 1...100 and `maxAgeHours`
  1...720.
- `news(id:)` maps to `GET /2/news/{id}`.
- `trendsByWoeid(woeid:maxTrends:)` maps to
  `GET /2/trends/by/woeid/{woeid}`.
- `recentPostCounts(query:...)` maps to `GET /2/tweets/counts/recent`.
- `bookmarks(maxResults:paginationToken:...)` maps to authenticated-user
  bookmark listing.
- `bookmarkFolders(maxResults:paginationToken:)` maps to
  `GET /2/users/{id}/bookmarks/folders`.
- `bookmarksByFolder(folderId:...)` maps to
  `GET /2/users/{id}/bookmarks/folders/{folder_id}`.
- `bookmarkPost(postId:)` and `removeBookmark(postId:)` map to authenticated-user
  bookmark add/remove mutations. Bookmark read/write fields are bearer-only in
  the Swift transport slice because the current endpoints require OAuth2 user
  context.
- `mutedUsers(...)` and `blockedUsers(...)` map to the corresponding
  authenticated X user-context endpoints.
- `likePost(...)`, `unlikePost(...)`, `followUser(...)`, `unfollowUser(...)`,
  `muteUser(...)`, and `unmuteUser(...)` map to authenticated-user social
  mutations.
- `list(...)`, `ownedLists(...)`, `followedLists(...)`, `listMemberships(...)`,
  `pinnedLists(...)`, `listFollowers(...)`, `listMembers(...)`, and
  `listPosts(...)` map to X List read endpoints. `pinnedLists` intentionally
  omits pagination parameters because `/2/users/{id}/pinned_lists` does not
  accept them.
- `createList(...)`, `updateList(...)`, `deleteList(...)`, member add/remove,
  follow/unfollow, and pin/unpin map to X List mutation endpoints. `updateList`
  returns `UpdateResult` because the upstream response contains `updated`, not a
  full List object.
- `dmEvents(...)`, `dmEvent(...)`, `dmConversationEvents(...)`, and
  `dmConversationEventsById(...)` map to Direct Message event reads.
- `createDirectMessage(...)`, `createDirectMessageInConversation(...)`,
  `createDirectMessageConversation(...)`, and `deleteDirectMessage(...)` map to
  Direct Message write/delete endpoints.
- `createArticleDraft(title:text:contentStateJSON:)` maps either plain text or
  caller-provided DraftJS `content_state` JSON into `POST /2/articles/draft`.
- `publishArticle(articleId:)` maps to `POST /2/articles/{article_id}/publish`.
- OpenAPI parity `OpenAPIResult` fields map JSON-compatible X API families that
  do not have stable high-level project objects yet: compliance jobs,
  Communities, Community Notes, analytics, insights, finite filtered-stream rule
  counts, post repost
  object reads, media lookup/upload initialization/finalization/metadata, user
  public-key and affiliate reads, user public-key registration, reposts-of-me,
  OpenAPI spec lookup, webhooks, activity subscriptions, account-activity
  subscriptions, raw encrypted Chat conversation primitives, media one-shot
  upload/append, Chat media upload initialization/append/finalization, and
  Chat/DM media download-to-file helpers.
- Spaces lookup/search fields are projected into typed `SpacePage` or `Space`
  results. Space buyers and posts reuse the existing typed `UserPage` and
  `PostPage` shapes.
- Filtered-stream rule reads and updates are projected into typed
  `StreamRulePage` and `StreamRuleUpdateResult` results.

## Known Gaps

Long-running stream consumption remains outside the short-lived GraphQL query
slice and is exposed through `x-gateway-reader stream sample|filtered`, which
uses bounded session lifecycle controls, cancellation through event/time limits,
retry-backed reconnects when requested, and NDJSON event output in normal CLI
mode. Finite stream rule reads and updates are typed; the rule-count endpoint is
exposed as a GraphQL `OpenAPIResult` field. Binary media
endpoints are exposed as file-path operations: uploads read local files and
downloads write raw response bytes to an explicit `outputPath`. Rich Article
bodies are supported through a validated `contentStateJSON` escape hatch; a
friendlier rich-text DSL can be added later without changing the underlying
payload support.

Live verification on 2026-06-30 showed Direct Message reads working for the
available token, while sending a DM to `landfall1793482` returned upstream 403
because X did not permit DMing that participant with the current token/app
state. No DM event was created in that failed attempt, so there was nothing to
delete.
