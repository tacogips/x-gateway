# x-gateway

AI-oriented command-line and TypeScript library gateway for X API operations.

The package exposes two binaries:

- `x-gateway`: full CLI surface for reviewed read and write operations
- `x-gateway-reader`: read-only CLI surface for account, post, search, timeline, and usage queries

It also exposes a TypeScript library entry point:

```ts
import { createXGatewayClient } from "x-gateway";
```

## Configuration

Configuration can come from environment variables or explicit library/CLI parameters.

Common environment variables:

- `X_GW_CONFIG_MODE`: `env`, `params`, or `mixed`
- `X_GW_TOKEN`: bearer token for raw GraphQL requests and bearer-compatible reads
- `X_GW_CONSUMER_KEY`
- `X_GW_CONSUMER_SECRET`
- `X_GW_ACCESS_TOKEN`
- `X_GW_ACCESS_TOKEN_SECRET`
- `X_GW_TIMEOUT_MS`
- `X_GW_RETRY`
- `X_GW_MEDIA_ROOT_DIR`
- `X_GW_STRICT_CAPABILITY_CHECKS`

OAuth1 credentials are required for OAuth1-backed reads and stable posting helpers.

## Read-Only GraphQL

Use `x-gateway-reader graphql query` for reviewed read operations:

```bash
x-gateway-reader graphql query 'query { accountMe { id username name } }' --json
```

```bash
x-gateway-reader graphql query 'query { followingTimeline(maxResults: 10, maxUsers: 25, maxResultsPerUser: 5) { posts { id text createdAt author { username name } metrics { impressionCount likeCount replyCount repostCount quoteCount bookmarkCount } } pageInfo { resultCount newestId oldestId nextToken } } }' --json
```

`followingTimeline(...)` is the stable field for fetching recent posts from accounts followed by the authenticated user when `homeTimeline` is empty or unavailable. It is a bounded project-owned aggregate over the authenticated user's follow graph, not a raw X home timeline cursor.

For followed-account timeline fanout, `followingTimeline(...)` requests public tweet fields only. It keeps `public_metrics`, does not request owner-only `organic_metrics` or `promoted_metrics` for other users, and returns `metrics.impressionCount` as `null` when no reviewed public impression source is available.

Do not pass `followingTimeline.paginationToken` until x-gateway ships a reviewed merged aggregate cursor. Current stable behavior is first-page bounded aggregation with no upstream cursor passthrough.

## Verification

Typical local verification commands:

```bash
bun run typecheck
bun test
bun run build
bun run format:check
git diff --check
```
