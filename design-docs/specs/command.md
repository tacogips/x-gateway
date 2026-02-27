# Command Design

This document defines the `x-gateway` CLI contract.

## Overview

`x-gateway` is an AI-oriented command-line client for X (Twitter) APIs.
The CLI must be scriptable, deterministic, and return structured diagnostics suitable for automated callers.

## Subcommands

### Auth and Session

- `x-gateway auth verify`
- `x-gateway auth scopes`
- `x-gateway auth whoami`

### Posting and Engagement

- `x-gateway post create`
- `x-gateway post reply`
- `x-gateway post quote`
- `x-gateway post repost`
- `x-gateway post delete`
- `x-gateway media upload`

### Timeline and Retrieval

- `x-gateway tweet get`
- `x-gateway tweet thread`
- `x-gateway timeline home`
- `x-gateway timeline user`
- `x-gateway mentions list`

### Social Graph

- `x-gateway users get`
- `x-gateway users lookup`
- `x-gateway users followers`
- `x-gateway users following`

### Interactions

- `x-gateway likes add`
- `x-gateway likes remove`
- `x-gateway bookmarks add`
- `x-gateway bookmarks remove`

### Account and Direct Message Scope

- `x-gateway account me`
- `x-gateway dm send`
- `x-gateway dm list`

### System

- `x-gateway health`
- `x-gateway version`

## Flags and Options

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--json` | boolean | `false` | Emit machine-readable JSON response envelope |
| `--pretty` | boolean | `false` | Pretty-print JSON output |
| `--trace-id` | string | auto | Request correlation id for logs and errors |
| `--auth-mode` | enum(`env`,`params`,`mixed`) | `mixed` | Credential resolution mode |
| `--dry-run` | boolean | `false` | Validate and plan request without mutating remote state |
| `--timeout-ms` | number | `30000` | Per-request timeout |
| `--retry` | number | `2` | Retry count for retryable errors |
| `--idempotency-key` | string | none | Idempotency control for create operations |

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `X_BEARER_TOKEN` | Conditional | none | Bearer token for app/user operations |
| `X_CONSUMER_KEY` | Conditional | none | OAuth 1.0a consumer key |
| `X_SECRET_KEY` | Conditional | none | OAuth 1.0a consumer secret |
| `X_ACCESS_TOKEN` | Conditional | none | OAuth 1.0a access token |
| `X_ACCESS_TOKEN_SECRET` | Conditional | none | OAuth 1.0a access token secret |
| `X_CLIENT_ID` | Conditional | none | OAuth 2.0 client id |
| `X_CLIENT_SECRET` | Conditional | none | OAuth 2.0 client secret |
| `X_API_BASE_URL` | No | provider default | Override API endpoint |
| `X_GATEWAY_OUTPUT` | No | `text` | Output mode (`text` or `json`) |

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

## Posting Pattern Coverage Requirements

`x-gateway` must explicitly support all publishing patterns used in X workflows:

- standard post
- reply to a post
- quote post and quote-source resolution
- repost and undo repost
- image/media post
- video/media post
- article or long-form publishing when available via API/product surface
- retrieval of referenced/original content for quote/reply/repost chains
