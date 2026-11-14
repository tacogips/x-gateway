# Command Design

This document defines the current Swift CLI contract for `x-gateway-read` and
`x-gateway-write`.

## Overview

The repository ships two AI-oriented Swift command-line clients for X (Twitter)
APIs:

- `x-gateway-read`: read-only project-owned GraphQL query access plus local
  diagnostics and capability inspection
- `x-gateway-write`: project-owned GraphQL mutation access plus local
  diagnostics and capability inspection

Both CLIs must be scriptable, deterministic, and return structured diagnostics suitable for automated callers.

Primary contract:

- `graphql query <query-or-mutation>` is the primary CLI contract for reviewed
  capabilities.
- `graphql schema` prints the owned public GraphQL schema.
- The `graphql` namespace refers to the project-owned `x-gateway` contract, not direct upstream X GraphQL.
- Unimplemented high-level commands must fail immediately with `UNSUPPORTED` and remediation that names the supported alternative.
- Detailed namespace rationale lives in `design-docs/specs/design-graphql-command-surface.md`.

## Command Policy

- `x-gateway-read` must reject all write/mutation documents with a stable
  `UNSUPPORTED` error and remediation to use `x-gateway-write`.
- `x-gateway-write` must reject read query documents with a stable
  `UNSUPPORTED` error and remediation to use `x-gateway-read`.
- Stable commands include the project-owned GraphQL contract, auth configuration diagnostics, capability inspection, and local system introspection.
- `graphql query <query>` must accept only project-owned GraphQL fields; it must not forward user input directly to raw X GraphQL.
- Commands must not expose raw X web GraphQL details through the public CLI surface.
- Unimplemented command groups (`tweet`, `timeline`, `users`, `likes`, `bookmarks`, `follows`, `dm`, etc.) must still be rejected unless and until a reviewed adapter is added explicitly.

## Subcommands

### Project-Owned GraphQL Contract

- `x-gateway-read graphql query '<query>'`
- `x-gateway-write graphql query '<mutation>'`
- `x-gateway-read graphql schema`
- `x-gateway-write graphql schema`

### Auth and Session

- `x-gateway-read auth verify`
- `x-gateway-read auth scopes`
- `x-gateway-write auth verify`
- `x-gateway-write auth scopes`

`auth verify` design rule:

- It must report capability-level readiness for the stable baseline, not only a single resolved auth family string.
- At minimum it must cover `account.me`, `usage.tweets`, `post.get`, `post.replies`, `timeline.search`, `timeline.home`, `timeline.following`, `timeline.user`, `timeline.mentions`, `post.create`, `post.delete`, `post.reply`, `post.quote`, `post.repost`, and `post.unrepost`.
- Each capability row must indicate whether it is ready with the current credentials and, when not ready, the blocking requirement (`missing auth`, `requires OAuth1`, or `requires user-context bearer`).

### System

- `x-gateway-read health`
- `x-gateway-read version`
- `x-gateway-write health`
- `x-gateway-write version`

## Flags and Options

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--json` | boolean | `false` | Emit machine-readable JSON response envelope |
| `--pretty` | boolean | `false` | Pretty-print JSON output |
| `--trace-id` | string | none | Optional request correlation id for logs and errors |
| `--config-mode` | enum(`env`,`params`,`mixed`) | `mixed` | Credential resolution mode |
| `--auth-mode` | enum(`env`,`params`,`mixed`) | deprecated alias | Deprecated alias for `--config-mode` |
| `--timeout-ms` | number | `30000` | Per-request timeout |
| `--retry` | number | `2` | Retry count for retryable errors |
| `--retry-backoff` | enum(`exponential-jitter`,`fixed`,`none`) | `exponential-jitter` | Retry delay strategy |
| `--retry-base-ms` | number | `300` | Base delay for backoff calculation |
| `--retry-max-ms` | number | `10000` | Upper bound for single retry delay |

## Environment Variables

Naming convention: all environment variables owned by this project must use the `X_GW_` prefix.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `X_GW_TOKEN` | Conditional | none | Primary bearer token for app/user operations |
| `X_GW_CONSUMER_KEY` | Conditional | none | OAuth 1.0a consumer key |
| `X_GW_CONSUMER_SECRET` | Conditional | none | OAuth 1.0a consumer secret |
| `X_GW_ACCESS_TOKEN` | Conditional | none | OAuth 1.0a access token |
| `X_GW_ACCESS_TOKEN_SECRET` | Conditional | none | OAuth 1.0a access token secret |
| `X_GW_CLIENT_ID` | Conditional | none | OAuth 2.0 client id |
| `X_GW_CLIENT_SECRET` | Conditional | none | OAuth 2.0 client secret |
| `X_GW_OUTPUT` | No | `text` | Output mode (`text` or `json`) |
| `X_GW_CONFIG_MODE` | No | `mixed` | Canonical config resolution mode |
| `X_GW_AUTH_MODE` | No | none | Legacy auth-type shell variable (`oauth1` or `bearer`); tolerated for compatibility but not used as the canonical config-mode name |
| `X_GW_RETRY` | No | `2` | Default retry count |
| `X_GW_RETRY_BACKOFF` | No | `exponential-jitter` | Backoff strategy |
| `X_GW_RETRY_BASE_MS` | No | `300` | Base delay in milliseconds |
| `X_GW_RETRY_MAX_MS` | No | `10000` | Maximum single delay in milliseconds |
| `X_GW_STRICT_CAPABILITY_CHECKS` | No | `false` | Enable stricter capability gating rules |

Note: Library consumers must be able to pass equivalent credentials/config via function parameters instead of environment variables.

Operational guidance rule:

- Repository-provided env examples must describe the current hybrid baseline accurately.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 2 | Invalid CLI input / validation failure |
| 3 | Authentication configuration missing or malformed |
| 4 | Authentication failed (expired/revoked/invalid credential) |
| 5 | Authorization/scope/permission denied |
| 6 | Resource not found |
| 7 | Conflict or duplicate/idempotency violation |
| 8 | Rate limited or quota exhausted |
| 9 | Upstream API contract or transport failure |
| 10 | Internal runtime error |

## Error Contract

CLI errors must include:

- failure summary (`what failed`)
- likely cause (`why it failed`)
- classification (`auth`,`permission`,`rate_limit`,`validation`,`network`,`upstream`)
- remediations (`what to do next`)
- trace metadata (`traceId`, request identifiers if available)

Auth diagnostic rules:

- `auth verify` must distinguish available credential families from capability readiness.
- Mixed-auth output must make it explicit that stable posting helpers remain OAuth1-backed while reviewed stable reads may choose bearer or OAuth1 per capability.
- Bearer-only output must not overclaim that `account me` is definitely live-ready unless the token is a user-context bearer; readiness for that capability should be reported as conditional with an explicit reason.

Project-owned GraphQL rules:

- `graphql query <query>` accepts the stable project-owned `x-gateway` GraphQL contract only.
- `graphql schema` prints the stable project-owned `x-gateway` GraphQL contract.
- The current parser accepts exactly one operation definition with exactly one
  top-level field per request and rejects multi-operation or multi-field
  documents before auth or live execution.
- Non-ignored tokens before or after the single operation definition must fail
  validation rather than being ignored while a supported root field executes.
- Fragments, aliases, directives, and variable argument values remain
  unsupported in the current parser and must fail with explicit validation
  diagnostics instead of being ignored.
- Supported top-level fields include `accountMe`, `apiUsage`, `post`, `searchPosts`, `homeTimeline`, `followingTimeline`, `userTimeline`, `mentionsTimeline`, `createPost`, `deletePost`, `replyToPost`, `quotePost`, `repostPost`, and `unrepostPost`.
- Reviewed nested field arguments are supported for `Post.replies(maxResults:, paginationToken:, ...)`.
- `followingTimeline(maxResults:, maxUsers:, maxResultsPerUser:, paginationToken:, includePromoted:, mediaRootDir:, downloadMedia:, forceDownload:)` is the canonical field for workflows that need latest posts from accounts followed by the authenticated user when `homeTimeline` is empty or unavailable for that account.
- Canonical mutation arguments are `deletePost(postId: ID!)`, `repostPost(postId: ID!)`, and `unrepostPost(postId: ID!)`.
- Canonical attachment arguments are supported on `createPost`, `replyToPost`, and `quotePost` with `attachments: [{ kind: "image", filePath: "...", altText: "..." }]`.
- The current public GraphQL parser supports string/integer/boolean/null/list/object literals only.
- Top-level GraphQL operation selection must be resolved from the root
  query/mutation field when present; nested projection field names must not
  change the selected operation or leak their arguments into top-level
  validation.
- Public root fields must reject unsupported root arguments before auth or live
  execution, while nested input-object fields such as `PostAttachmentInput.kind`
  remain scoped to their owning validator.
- Operation signatures, including operation names and variable-definition
  parentheses, must be skipped when locating the root selection set. Variables
  remain unsupported as public argument values until reviewed explicitly.
- Documents containing additional query/mutation operation definitions must not
  be partially executed by selecting only the first supported operation.
- `x-gateway-read` must reject `graphql query` mutations.
- `x-gateway-write` must reject `graphql query` read documents.

Capability adapter rules:

- `account me` must select an auth-appropriate identity endpoint internally rather than requiring the caller to choose a transport.
- `post get` must select a stable public lookup adapter internally and expand referenced posts when the upstream transport provides them.
- `post replies` must select the reviewed recent-search adapter internally and keep direct-reply semantics scoped to the requested parent post id.
- Nested `Post.replies(...)` must dispatch through the same reviewed `post.replies` capability and remain bounded to avoid unreviewed unbounded fan-out.
- Post metrics must use nullable fields in the stable payload so missing upstream metric access yields `null` rather than a failed post query.
- `likes list` must remain rejected until a reviewed live adapter route is verified; capability inventory and auth diagnostics must not advertise liked-post reads as part of the stable contract while the live path is known to fail.
- `followingTimeline` must use an authenticated-user read path, not public search inference. The reviewed adapter should prefer OAuth1 when configured and may treat bearer readiness as conditional on a user-context bearer token.
- `followingTimeline` must return stable `PostPage` output with author data through the existing author shape, nullable metrics including `impressionCount`, existing media options, and existing promoted-post filtering semantics.
- `followingTimeline` followed-account timeline fetches must not request owner-only `organic_metrics` or `promoted_metrics`; public metrics should still be requested, and unavailable impression counts must remain `null` instead of failing the page.
- `followingTimeline` aggregate pagination must be explicit and defensible; until a reviewed merged-cursor design is implemented, the command may expose only first-page bounded aggregation with no misleading upstream cursor passthrough.
- `post create` must prefer a stable public API adapter when public REST support is sufficient.
- `post delete` must prefer a stable public API adapter when public REST support is sufficient.
- `post reply`, `post quote`, `post repost`, and `post unrepost` must prefer stable public API adapters when public REST support is sufficient.
- When both bearer and OAuth1 credentials are configured, stable posting helpers
  must prefer OAuth1 instead of failing just because bearer is also present.
- `x-gateway-read` must reject write-oriented capability behavior such as
  `createPost`.
- Attachment-backed stable posting helpers require OAuth1 because media upload
  and alt-text application use the OAuth1 media upload path.

Retry behavior rules:

- Retry is enabled only for retryable classes (`NETWORK_FAILURE`, transient `UPSTREAM_FAILURE`, and explicit rate-limit recoverable responses).
- Default strategy is exponential backoff with jitter.
- Non-retryable classes (`VALIDATION_ERROR`, `PERMISSION_DENIED`, `AUTH_INVALID`, `AUTH_REVOKED`) must fail immediately.
- Error output for exhausted retries must include attempt count, total wait time, and last failure cause.

When `--json` is enabled, all failures use a stable envelope:

```json
{
  "ok": false,
  "error": {
    "code": "AUTH_EXPIRED",
    "summary": "Access token rejected by X API",
    "details": "The OAuth token is expired or revoked.",
    "likelyCauses": [
      "Token expired",
      "Token revoked from developer portal"
    ],
    "remediations": [
      "Refresh/reissue token",
      "Re-run with credentials that include write scope"
    ],
    "httpStatus": 401,
    "traceId": "xgw_..."
  }
}
```

## Deferred High-Level Coverage Requirements

`x-gateway` must explicitly support all publishing patterns used in X workflows:

- standard post
- reply to a post
- quote post and quote-source resolution
- repost and undo repost
- image/media post
- video/media post
- article or long-form publishing when available via API/product surface
- retrieval of referenced/original content for quote/reply/repost chains

Current implementation note:

- The current implementation exposes the project-owned GraphQL public request surface plus local auth diagnostics, capability inspection, health, and version commands.
- The canonical path is the project-owned GraphQL public request surface, which resolves onto the same reviewed capabilities instead of leaking raw X transport details as the main contract.
- `likes list` is intentionally withheld from the stable CLI, SDK, and public GraphQL contract until a reviewed live adapter route is verified.
- `account me` can use OAuth1 or a user-context bearer token; attachment-backed
  stable posting helpers currently require OAuth1.
- `post get` can use OAuth1 or bearer-token reads through the public lookup API, and it prefers OAuth1 when both are configured.
- Stable posting helpers prefer OAuth1 whenever it is configured.
- Stable `createPost`, `replyToPost`, and `quotePost` support inline image attachments through internal OAuth1 media upload and alt-text application; callers do not provide raw upload sequencing.
- Stable `Post.replies(...)` allows recursive direct-reply traversal within one GraphQL request, subject to a bounded per-request expansion limit.
- Stable `followingTimeline(...)` is the intended rielflow X digest read field for followed-account latest-post retrieval. The concrete downstream reference is `/Users/taco/gits/tacogips/rielflow/examples/x-follower-ai-business-digest/workflow.json`, whose `fetch-follower-posts` node runs `rielflow/x-gateway-read` through Docker image `ghcr.io/tacogips/x-gateway:latest` and queries `followingTimeline { posts { ... metrics { ... impressionCount } } pageInfo { ... } }`. Treat that workflow as a behavioral consumer reference only: implementation should preserve the `followingTimeline` -> `PostPage` -> nullable `metrics.impressionCount` data flow without copying code from the rielflow repository.
- Support is counted only when the reviewed auth path is actually enforced by the adapter contract; latent placeholder methods inside the wrong auth adapter do not count as delivered capability support.
- Deferred commands must still fail explicitly with `UNSUPPORTED` and remediation that keeps `graphql query` as the canonical surface for reviewed capabilities.

## Swift Split Commands

The Swift package exposes installable read and write command products:

- `x-gateway-read`: read-only command. It accepts read diagnostics and schema commands, rejects GraphQL mutations before live execution, and currently supports `accountMe`, `post`, `searchPosts`, `homeTimeline`, `followingTimeline`, `userTimeline`, and `mentionsTimeline` with OAuth1-preferred signing plus bearer fallback. `apiUsage` remains bearer-token only.
- `x-gateway-write`: write command. It accepts write diagnostics and schema commands, rejects GraphQL read queries before live execution, and currently supports `createPost`, `deletePost`, `replyToPost`, `quotePost`, `repostPost`, and `unrepostPost` with OAuth1-preferred signing plus bearer fallback. Attachment-backed `createPost`, `replyToPost`, and `quotePost` require OAuth1 for media upload.

The Swift split is an installation boundary as well as a runtime safety
boundary. Installers may build and copy only `x-gateway-read` or only
`x-gateway-write` from SwiftPM products, and the shared `XGatewayCore` library
must enforce the operation split so entrypoints cannot drift.

The Swift write command parses and validates `attachments` on `createPost`,
`replyToPost`, and `quotePost`. Valid attachment input uploads image files
through the OAuth1 media upload path, applies alt text when provided, and posts
with the resulting `media_ids`; malformed attachment input fails with
`VALIDATION_ERROR`, and bearer-only attachment attempts fail with an OAuth1
auth remediation before any text-only post can be created.

Swift read projections include stable post metrics, author profiles, media
asset URLs, and referenced-post shortcuts from upstream expansions. Swift read
fields accept `includePromoted`; promoted posts are filtered by default when
upstream promotion metrics identify them. Swift read fields also accept
`mediaRootDir`, `downloadMedia`, and `forceDownload`; downloaded media is
stored under `mediaRootDir/<post-id>/`, existing files are reused unless forced,
and `downloadMedia: false` keeps the response source-only. Nested
`Post.replies(...)` selections are hydrated through bounded Swift reply-search
lookups and reject unsupported nested arguments before live execution.
