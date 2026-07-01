---
name: x-read-via-reader
description: Use when reading data from X/Twitter with x-gateway-reader. Covers auth preflight, schema inspection, and read-only project-owned GraphQL queries such as account lookup, post lookup, search, timelines, Lists, DMs, social graph reads, and usage. Do not use for posting or other mutations.
allowed-tools: Read, Grep, Glob, Bash
---

# X Read Via Reader

Use this skill when the task is to inspect or retrieve X data without performing writes.

## Binary

Use `x-gateway-reader`.

This binary is read-only. It must not be used for `createPost`, `quotePost`, `repostPost`, or any other mutation.

## Workflow

1. Run `x-gateway-reader auth verify` when auth readiness is relevant.
2. Run `x-gateway-reader graphql schema` if you need to confirm the current public GraphQL contract.
3. Prefer `x-gateway-reader graphql query '<graphql>'` for reviewed read operations.
4. Use `--json` when another agent or tool will parse the result.

## Read Operations

Prefer the project-owned GraphQL surface instead of ad hoc legacy commands.

Common queries:

```bash
x-gateway-reader graphql query 'query { accountMe { id username name } }'
```

```bash
x-gateway-reader graphql query 'query { post(id: "123") { id text author { username } referencedPosts { id relation } } }'
```

```bash
x-gateway-reader graphql query 'query { post(id: "123") { id text replies(maxResults: 10) { posts { id text replies(maxResults: 10) { pageInfo { resultCount } } } pageInfo { resultCount } } } }'
```

```bash
x-gateway-reader graphql query 'query { searchPosts(query: "openai", maxResults: 5) { posts { id text author { username } } pageInfo { resultCount nextToken } } }'
```

```bash
x-gateway-reader graphql query 'query { homeTimeline(maxResults: 10) { posts { id text } pageInfo { resultCount nextToken } } }'
```

```bash
x-gateway-reader graphql query 'query { followingTimeline(maxResults: 10, maxUsers: 25, maxResultsPerUser: 5) { posts { id text createdAt author { username name } metrics { impressionCount likeCount replyCount repostCount quoteCount bookmarkCount } } pageInfo { resultCount newestId oldestId nextToken } } }'
```

```bash
x-gateway-reader graphql query 'query { userTimeline(userId: "user-42", maxResults: 10) { posts { id text } pageInfo { resultCount nextToken } } }'
```

```bash
x-gateway-reader graphql query 'query { followers(userId: "user-42", maxResults: 10) { users { id username name } pageInfo { resultCount nextToken } } }'
```

```bash
x-gateway-reader graphql query 'query { following(userId: "user-42", maxResults: 10) { users { id username name } pageInfo { resultCount nextToken } } }'
```

```bash
x-gateway-reader graphql query 'query { usersByUsernames(usernames: ["xdev", "twitterdev"]) { users { id username name } pageInfo { resultCount } } }'
```

```bash
x-gateway-reader graphql query 'query { likedPosts(userId: "user-42", maxResults: 10) { posts { id text } pageInfo { resultCount nextToken } } }'
```

```bash
x-gateway-reader graphql query 'query { ownedLists(userId: "user-42", maxResults: 10) { lists { id name private } pageInfo { resultCount } } }'
```

```bash
x-gateway-reader graphql query 'query { dmEvents(maxResults: 10, eventTypes: ["MessageCreate"]) { events { id eventType conversationId senderId text } pageInfo { resultCount nextToken } } }'
```

```bash
x-gateway-reader graphql query 'query { mentionsTimeline(userId: "user-42", maxResults: 10) { posts { id text } pageInfo { resultCount nextToken } } }'
```

```bash
x-gateway-reader graphql query 'query { apiUsage(days: 14) { projectId projectUsage dailyProjectUsage { usage { date usage } } } }'
```

OpenAPI parity reads return `OpenAPIResult { ok payload }` for lower-level X
API families that are not modeled as stable post/user/List objects yet:

```bash
x-gateway-reader graphql query 'query { postAnalytics(postIds: ["123"], startTime: "2026-01-01T00:00:00Z", endTime: "2026-01-02T00:00:00Z", granularity: "day") { ok payload } }'
```

```bash
x-gateway-reader graphql query 'query { complianceJobs(type: "tweets") { ok payload } }'
```

## Guardrails

- If the user asks to post, repost, quote, reply, delete, or otherwise mutate X state, stop using this skill and switch to the `x-post-via-gateway` skill.
- If a query fails validation, inspect `x-gateway-reader graphql schema` and rewrite the request to match the public schema.
- Prefer stable project-owned GraphQL fields over raw upstream GraphQL shapes.
- Use `followers` and `following` when the caller needs follow-graph user lists.
- Use `mutedUsers`, `blockedUsers`, List reads, and DM event reads only with an OAuth2 bearer token that has the required X scopes.
- Use OpenAPI parity reads such as compliance, Communities, Community Notes,
  analytics, insights, post repost objects, media lookup/status, OpenAPI spec
  lookup, public keys, webhooks, and Chat/DM media download-to-file helpers,
  subscriptions, and raw Chat reads only with an OAuth2 bearer token and
  endpoint-specific X access.
- Spaces, streaming, and stream connection management are intentionally not read
  through this skill.
- Use `followingTimeline` for followed-account latest-post retrieval when `homeTimeline` is empty or unavailable for the authenticated account. It is a bounded project-owned aggregate over the authenticated user's follow graph, not a raw X home timeline.
- `followingTimeline` followed-account fanout requests public tweet fields only: it keeps `public_metrics`, omits owner-only `organic_metrics` and `promoted_metrics` for other users, and leaves `metrics.impressionCount` as `null` when no reviewed public impression source is available.
- Do not pass `followingTimeline.paginationToken` until x-gateway ships a reviewed merged aggregate cursor; the current stable behavior is first-page aggregation with no upstream cursor passthrough.
