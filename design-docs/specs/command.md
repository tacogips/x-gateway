# Command Design

This document defines the CLI contract for `x-gateway` and `x-gateway-reader`.

## Overview

The repository ships two AI-oriented command-line clients for X (Twitter) APIs:

- `x-gateway`: GraphQL query + mutation operations
- `x-gateway-reader`: GraphQL query-only operations

Both CLIs must be scriptable, deterministic, and return structured diagnostics suitable for automated callers.

Primary contract:

- `graphql request` is the primary supported network command for both binaries.
- Local diagnostics commands are also supported when they do not require an unmapped upstream operation.
- Unmapped high-level endpoint commands are out of the stable CLI contract and must fail immediately with `UNSUPPORTED`.

## Command Policy

- `x-gateway-reader` must reject all write/mutation commands with a stable `UNSUPPORTED` error and remediation to use `x-gateway`.
- Stable commands are limited to raw GraphQL request execution, auth configuration diagnostics, capability inspection, and local system introspection.
- Legacy command groups that imply hidden GraphQL mappings (`post`, `tweet`, `timeline`, `users`, `likes`, `bookmarks`, `follows`, `account`, `dm`, etc.) must be rejected unless and until a reviewed mapping is added back explicitly.

## Subcommands

### Raw GraphQL

- `x-gateway graphql request`
- `x-gateway-reader graphql request` (query-only)

### Auth and Session

- `x-gateway auth verify`
- `x-gateway auth scopes`
- `x-gateway-reader auth verify`
- `x-gateway-reader auth scopes`

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
| `--auth-mode` | enum(`env`,`params`,`mixed`) | `mixed` | Credential resolution mode |
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
| `X_GW_AUTH_MODE` | No | `mixed` | Default auth resolution mode |
| `X_GW_RETRY` | No | `2` | Default retry count |
| `X_GW_RETRY_BACKOFF` | No | `exponential-jitter` | Backoff strategy |
| `X_GW_RETRY_BASE_MS` | No | `300` | Base delay in milliseconds |
| `X_GW_RETRY_MAX_MS` | No | `10000` | Maximum single delay in milliseconds |
| `X_GW_STRICT_CAPABILITY_CHECKS` | No | `false` | Enable stricter capability gating rules |

Note: Library consumers must be able to pass equivalent credentials/config via function parameters instead of environment variables.

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

GraphQL request rules:

- Every live GraphQL request must include `operationName`.
- A live GraphQL request must include exactly one request source: persisted `documentId` or inline `query`.
- `variables-json`, `features-json`, and `field-toggles-json` must be JSON objects when provided.
- `--graphql-base-url` and `X_GW_GRAPHQL_BASE_URL` target the GraphQL transport only; the stable surface no longer exposes a generic API-base override.
- Deprecated alias inputs such as `--api-base-url` must fail validation; they must not be accepted as hidden compatibility shims.
- Only boolean flags may use bare `--flag` form; string/number/JSON flags must provide an explicit value.
- `x-gateway-reader` must reject `graphql request --operation-type mutation`.
- Unknown commands, unknown flags, and invalid global flag values must fail with `VALIDATION_ERROR`; they must not be ignored or silently fall back to defaults.

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
    "code": "AUTH_TOKEN_EXPIRED",
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

- The current GraphQL-only iteration does not yet satisfy these high-level requirements.
- Until concrete GraphQL mappings are committed, related commands are intentionally absent from the stable CLI surface and must fail explicitly with `UNSUPPORTED` and remediation to use `graphql request` or add the missing mapping.
