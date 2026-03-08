# Command Design

This document defines the CLI contract for `x-gateway` and `x-gateway-reader`.

## Overview

The repository ships two AI-oriented command-line clients for X (Twitter) APIs:

- `x-gateway`: stable capability commands plus low-level GraphQL query/mutation access
- `x-gateway-reader`: read-only capability commands plus low-level GraphQL query access

Both CLIs must be scriptable, deterministic, and return structured diagnostics suitable for automated callers.

Primary contract:

- Stable capability-oriented commands are the primary CLI contract.
- `api request` is the stable project-owned GraphQL-shaped contract for callers that want a single request document instead of command-specific flags.
- `graphql request` remains available as a low-level escape hatch for explicit GraphQL access.
- Capability inventory output must label these surfaces distinctly so `graphql request` is not mistaken for a peer stable contract.
- Unimplemented high-level commands must fail immediately with `UNSUPPORTED` and remediation that names the supported alternative.

## Command Policy

- `x-gateway-reader` must reject all write/mutation commands with a stable `UNSUPPORTED` error and remediation to use `x-gateway`.
- Stable commands include implemented capability adapters, auth configuration diagnostics, capability inspection, local system introspection, and low-level GraphQL access.
- `api request` must accept only project-owned GraphQL fields; it must not forward user input directly to raw X GraphQL.
- Commands must not expose raw X web GraphQL details unless the user explicitly chooses the low-level `graphql request` surface.
- The `graphql request` implementation must stay isolated from the stable capability planner so raw transport concerns do not become accidental stable-contract behavior.
- Unimplemented command groups (`tweet`, `timeline`, `users`, `likes`, `bookmarks`, `follows`, `dm`, etc.) must still be rejected unless and until a reviewed adapter is added explicitly.

## Subcommands

### Stable Capability Commands

- `x-gateway account me`
- `x-gateway post get --post-id <postId>`
- `x-gateway likes list --user-id <userId> [--limit <count>]`
- `x-gateway post create --text <text>`
- `x-gateway post delete --post-id <postId>`
- `x-gateway post reply --text <text> --reply-to-post-id <postId>`
- `x-gateway post quote --text <text> --quoted-post-id <postId>`
- `x-gateway post repost --post-id <postId>`
- `x-gateway post unrepost --post-id <postId>`

### Project-Owned GraphQL Contract

- `x-gateway api request --query <graphql>`
- `x-gateway-reader api request --query <graphql>` (query-only)

### Raw GraphQL

- `x-gateway graphql request`
- `x-gateway-reader graphql request` (query-only)

### Auth and Session

- `x-gateway auth verify`
- `x-gateway auth scopes`
- `x-gateway-reader auth verify`
- `x-gateway-reader auth scopes`

`auth verify` design rule:

- It must report capability-level readiness for the stable baseline, not only a single resolved auth family string.
- At minimum it must cover `graphql.request`, `account.me`, `post.get`, `likes.list`, `post.create`, `post.delete`, `post.reply`, `post.quote`, `post.repost`, and `post.unrepost`.
- Each capability row must indicate whether it is ready with the current credentials and, when not ready, the blocking requirement (`missing auth`, `requires OAuth1`, or `requires user-context bearer`).

### System

- `x-gateway health`
- `x-gateway version`
- `x-gateway-reader health`
- `x-gateway-reader version`

## Flags and Options

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--json` | boolean | `false` | Emit machine-readable JSON response envelope |
| `--pretty` | boolean | `false` | Pretty-print JSON output |
| `--trace-id` | string | none | Optional request correlation id for logs and errors |
| `--config-mode` | enum(`env`,`params`,`mixed`) | `mixed` | Credential resolution mode |
| `--auth-mode` | enum(`env`,`params`,`mixed`) | deprecated alias | Deprecated alias for `--config-mode` |
| `--operation-type` | enum(`query`,`mutation`) | `query` | GraphQL operation kind for policy/validation |
| `--operation-name` | string | none | GraphQL operation name |
| `--document-id` | string | none | Persisted GraphQL document id |
| `--query` | string | none | Inline GraphQL document when no persisted id is used |
| `--variables-json` | JSON object | none | GraphQL variables payload |
| `--features-json` | JSON object | none | GraphQL features payload |
| `--field-toggles-json` | JSON object | none | GraphQL field toggles payload |
| `--graphql-base-url` | string | provider default | Override the GraphQL base endpoint only |
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
| `X_GW_GRAPHQL_BASE_URL` | No | provider default | Override GraphQL endpoint |
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

- Repository-provided env examples must describe the current hybrid baseline accurately: OAuth1 credentials power the stable posting baseline, while bearer auth remains required for raw `graphql request`.

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
- Mixed-auth output must make it explicit that raw GraphQL remains bearer-backed while stable posting helpers remain OAuth1-backed.
- Bearer-only output must not overclaim that `account me` is definitely live-ready unless the token is a user-context bearer; readiness for that capability should be reported as conditional with an explicit reason.

GraphQL request rules:

- Every live GraphQL request must include `operationName`.
- A live GraphQL request must include exactly one request source: persisted `documentId` or inline `query`.
- `variables-json`, `features-json`, and `field-toggles-json` must be JSON objects when provided.
- `--graphql-base-url` and `X_GW_GRAPHQL_BASE_URL` target the GraphQL transport only; the stable surface no longer exposes a generic API-base override.
- Deprecated alias inputs such as `--api-base-url` must fail validation; they must not be accepted as hidden compatibility shims.
- Only boolean flags may use bare `--flag` form; string/number/JSON flags must provide an explicit value.
- `x-gateway-reader` must reject `graphql request --operation-type mutation`.
- Unknown commands, unknown flags, and invalid global flag values must fail with `VALIDATION_ERROR`; they must not be ignored or silently fall back to defaults.

Project-owned GraphQL rules:

- `api request --query` accepts the stable `x-gateway` GraphQL-shaped contract only.
- The initial parser may support only one top-level field per request.
- Variables, fragments, aliases, and directives may remain unsupported in the first slice if diagnostics are explicit.
- Supported initial top-level fields are `accountMe`, `post`, `likedPosts`, `createPost`, `deletePost`, `replyToPost`, `quotePost`, `repostPost`, and `unrepostPost`.
- `x-gateway-reader` must reject `api request` mutations.

Capability adapter rules:

- `account me` must select an auth-appropriate identity endpoint internally rather than requiring the caller to choose a transport.
- `post get` must select a stable public lookup adapter internally and expand referenced posts when the upstream transport provides them.
- `likes list` must select a stable public liked-posts adapter internally rather than exposing upstream query details.
- `post create` must prefer a stable public API adapter over raw X web GraphQL when public REST support is sufficient.
- `post delete` must prefer a stable public API adapter over raw X web GraphQL when public REST support is sufficient.
- `post reply`, `post quote`, `post repost`, and `post unrepost` must prefer stable public API adapters over raw X web GraphQL when public REST support is sufficient.
- When both bearer and OAuth1 credentials are configured, stable posting helpers must prefer OAuth1 instead of failing just because bearer is also present.
- `x-gateway-reader` must reject write-oriented capability commands such as `post create`.
- Stable posting helpers are currently an OAuth1-backed baseline only; bearer-token create/delete/reply/quote/repost flows must remain rejected until a reviewed user-context auth path is implemented.

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

- The current implementation restores a modest hybrid baseline: local auth diagnostics, `account me`, `post get`, `likes list`, and core posting flows (`post create`, `post delete`, `post reply`, `post quote`, `post repost`, `post unrepost`) are stable commands, while media, article, and broader timeline/social-graph patterns remain deferred.
- The next architectural slice adds a project-owned GraphQL-shaped public request path that resolves onto the same reviewed capabilities instead of leaking raw X web GraphQL as the main contract.
- `likes list` uses the same stable capability planner path as the rest of the read baseline; callers do not need to know whether the upstream implementation is REST or GraphQL.
- `account me` can use OAuth1 or a user-context bearer token; the stable posting helpers currently require OAuth1.
- `post get` can use OAuth1 or bearer-token reads through the public lookup API, and it prefers OAuth1 when both are configured.
- Stable posting helpers prefer OAuth1 whenever it is configured, even if bearer auth is also present for raw GraphQL access.
- Support is counted only when the reviewed auth path is actually enforced by the adapter contract; latent placeholder methods inside the wrong auth adapter do not count as delivered capability support.
- Deferred commands must still fail explicitly with `UNSUPPORTED` and remediation to use `graphql request` or wait for the missing adapter.
