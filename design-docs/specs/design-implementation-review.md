# Implementation and Specification Review

Review of the x-gateway Swift implementation (Sources/XGatewayCore, CLI entry
points, tests, packaging) against the product direction in CLAUDE.md and the
design specs under `design-docs/specs/`. This document records problems and
improvement opportunities only; no code changes are made by this review.

Review date: 2026-07-02. Reviewed revision: `a419d8c` (main).

Severity legend:

- **P1**: Correctness or data-integrity risk in normal usage.
- **P2**: Spec-vs-implementation mismatch, missing capability, or robustness
  gap likely to bite users/agents.
- **P3**: Design/maintainability/performance improvement.

## Summary

The codebase is a coherent single-purpose CLI with an unusually disciplined
error-payload model and a broad X API surface. The main problems cluster in
five areas:

1. Retry logic can duplicate non-idempotent writes (P1).
2. Owner-only metric fields are requested on every post read, contradicting
   the architecture spec and risking upstream 4xx failures (P1).
3. Several accepted inputs are silently ignored: timeline `paginationToken`
   arguments, the `--config-mode`/`--auth-mode`/`--strict-capability-checks`
   flags, and GraphQL selection sets (P1/P2).
4. The promised Swift library interface does not exist beyond the CLI facade;
   `XGatewayLiveExecutor` and all operations are internal (P2).
5. Structural duplication: three parallel projector helper sets, two
   near-identical chunked media-upload implementations, duplicated
   synchronous-request plumbing, and four registries that must stay manually
   aligned (P3).

## P1 Findings

### P1-1: Retry can duplicate non-idempotent mutations

`XGatewayLiveExecutor.performRequestWithRetry`
(`Sources/XGatewayCore/XGatewayLiveExecutor.swift:480`) retries any error whose
payload is `retryable`. `mapHTTPError` marks all HTTP 5xx and every network
failure as retryable. The same retry wrapper is used for `POST /2/tweets`
(createPost, replyToPost, quotePost), reposts, DM sends, and list mutations.

- A network failure after the request reached X (response lost) or a 5xx
  returned after side effects were applied leads to a duplicate post, duplicate
  DM, or duplicate repost. The default `retry` count is 2, so a single flaky
  response can post three times.
- X v2 has no idempotency-key mechanism, so the client must be conservative.

Recommended direction: default `retryCount` to 0 for mutation operations (or
retry only on connection-refused-before-send classes of failure), keep the
current behavior for GET reads, and document the difference in `command.md`.

Remediation status (2026-07-02): implemented a method-aware transport retry
policy. Retryable `GET` requests keep the configured retry budget; non-`GET`
requests, including write mutations and upload requests, use zero automatic
retries because X v2 does not expose idempotency keys. The behavior is covered
by XCTest policy coverage and documented in `command.md`.

### P1-2: Owner-only metrics requested on every post read

`timelineQueryItems` (`Sources/XGatewayCore/XGatewayLiveRequestEncoding.swift:67`)
defaults `includeOwnerMetrics: true`, so `tweet.fields` includes
`organic_metrics,promoted_metrics` for `post`, `posts`, `searchPosts`,
`searchAllPosts`, `userTimeline`, `mentionsTimeline`, `homeTimeline`,
`postQuotes`, `listPosts`, bookmarks, liked posts, and the reply-hydration
search.

- `architecture.md` states: "Owner-only metric groups may be used only by a
  reviewed self-owned read path where the authenticated user is permitted to
  access those metrics." Only the `followingTimeline` fanout and the stream
  request pass `includeOwnerMetrics: false`; everything else violates this.
- The X API rejects `organic_metrics`/`promoted_metrics` requests for tweets
  the authenticated user does not own (and for app-only tokens), so ordinary
  lookups of other users' posts can fail with upstream 400/403 that x-gateway
  then mislabels (see P2-6).

Recommended direction: invert the default to public metrics only, and add an
explicit reviewed opt-in (argument or capability) for self-owned reads that
need owner metrics. `detectPromotionStatus` in the projector must then handle
the "metrics never requested" case explicitly (it already returns `UNKNOWN`).

### P1-3: Timeline pagination arguments are accepted and silently dropped

`SupportedGraphQLFieldArguments.timeline`/`userTimeline`/`searchPosts` include
`paginationToken` via `GraphQLArgumentSet.pagedPostReadOptions`
(`Sources/XGatewayCore/XGatewayGraphQLArguments.swift:11`), so validation
accepts it. But `parseNativeGraphQLQueryOperation`
(`Sources/XGatewayCore/XGatewayGraphQLOperationParsing.swift:592`) never
extracts it, and the executor never sends `pagination_token` upstream for
`searchPosts`, `homeTimeline`, `userTimeline`, `mentionsTimeline`, or
`followingTimeline`.

- The response `pageInfo.nextToken` is populated from upstream, so callers are
  handed a token that has no effect when passed back. For an agent-facing tool
  this is a silent wrong-result failure: page 2 returns page 1 again.
- `command.md` explicitly says `followingTimeline` must not accept
  `paginationToken` "until a reviewed merged cursor exists" - the current
  behavior is to accept and ignore it, which is the opposite of the documented
  fail-loud policy.

Recommended direction: either wire `pagination_token` through for the native
timelines (upstream supports it for all of them except the synthetic
`followingTimeline`), or remove `paginationToken` from those fields' allowed
argument sets so it fails validation. `followingTimeline` should reject it.

### P1-4: Declared-but-ignored global flags

`globalFlagNames` (`Sources/XGatewayCore/XGatewayCore.swift:103`) includes
`config-mode`, `auth-mode`, and `strict-capability-checks`, but nothing ever
reads them. A user passing `--auth-mode oauth1` or
`--strict-capability-checks true` gets no error and no behavior change.

This directly conflicts with the CLAUDE.md error-handling requirement that
operational errors be explanatory: a misspelled or unimplemented control knob
should fail, not no-op. Remove them from the allowed set or implement them.

### P1-5: GraphQL selection sets are not honored in responses

The parser validates nested selections syntactically (rejecting fragments,
aliases, directives) and uses them to detect `replies(...)` expansion, but the
executor/projector always returns the full projected object regardless of the
fields the caller selected. `{ post(id: "1") { id } }` returns id, text,
metrics, promotionStatus, referencedPosts, media, and more.

`design-public-graphql-contract.md` requires that "Validation errors must also
reject unsupported selection fields instead of silently ignoring them" - today
a selection of a nonexistent field like `{ post(id: "1") { bogusField } }` is
accepted and the caller cannot tell it selected nothing real.

Recommended direction (either is defensible, pick one and document it):

- Minimal: validate selected field names against the schema and error on
  unknown fields, while still returning full objects.
- Full: apply the selection as a response filter after projection.

### P1-6: `--app-token` cannot be provided as a flag; `appToken` aliases `--token`

`readGlobalFlags` (`Sources/XGatewayCore/XGatewayCore.swift:461`) builds
`appToken: try optionalStringFlag(parsed, key: "token")` - the same key as
`token`. There is no `app-token` entry in `globalFlagNames` at all.

- `X_GW_APP_TOKEN` works via environment, but the documented flag-parity
  principle (env vars and explicit parameters both supported) is broken for
  the app-only credential.
- Because `appToken` is silently populated from `--token`, an operation that
  "prefers app-only" (`searchAllPosts`, `recentPostCounts`, stream rules) will
  treat a user-context `--token` as the app token, which changes failure modes
  in confusing ways.

Fix: add `--app-token` to `globalFlagNames` and read it under its own key.

### P1-7: Boolean/greedy flag parsing consumes following positionals

`parseArguments` (`Sources/XGatewayCore/XGatewayCore.swift:411`) treats the
next non-`--` token as the value of any flag. Boolean flags therefore swallow
positionals:

- `x-gateway-reader --json health` fails with "Flag --json must be a boolean
  value" because `health` is consumed as the value of `--json`.
- `x-gateway-reader --pretty graphql schema` fails the same way.

Flags only work reliably after all positionals, which is undocumented and
surprising for agents that assemble commands programmatically. Fix options:
maintain a set of known boolean flags that never consume a following token, or
require `--flag=value` syntax for values on boolean-typed flags.

## P2 Findings

### P2-1: No Swift library API despite the product requirement

CLAUDE.md requires "Swift library interface (`import XGatewayCore`)" with
configuration "accepted by ... explicit function parameters (for embedders
that avoid environment coupling)". In practice:

- `XGatewayLiveExecutor`, `SupportedGraphQLOperation`, `TransportSettings`,
  and every operation function are `internal`.
- The only public entry point is `XGatewayCLI.run(arguments:environment:)`,
  which returns pre-serialized JSON strings. Embedders must construct argv
  arrays and parse stdout text - a shell-style interface, not a library.
- Public helpers that do exist (`XGatewayResponseProjector`,
  `XGatewayOAuth1Signer`, `XGatewayArticleRequestBuilder`) are lower-level
  pieces, not a usable client.

Recommended direction: design a small public client type (for example
`XGatewayClient(configuration:)` with typed or `[String: Any]` results and
`XGatewayErrorPayload` thrown), keeping the CLI as a thin wrapper over it.
This also removes the blocking-thread problem for embedders (see P3-2).

### P2-2: OAuth2 loopback server accepts exactly one connection

`XGatewayLoopbackHTTPServer` (`Sources/XGatewayCore/XGatewayOAuth2.swift:442`)
calls `listen(fd, 1)` and `acceptOneCallback` handles a single connection,
then the flow either succeeds or throws.

- Any stray request to the port - a browser favicon probe, a speculative
  preflight, a port scanner, a duplicate tab - consumes the single accept and
  aborts the whole authorization with "path did not match" or "state did not
  match", forcing the user to restart.
- Robust loopback receivers loop on accept, respond 404 to non-matching
  requests, and keep waiting for the real callback until the deadline.

### P2-3: `localhost` redirect URIs bind IPv4 only

`LoopbackRedirectURI` maps `localhost` to `127.0.0.1` and the server binds
`AF_INET` only. On systems where the browser resolves `localhost` to `::1`
first (common on modern macOS), the redirect connection is refused and the
flow times out with a misleading "browser authorization was not completed"
error. Either bind dual-stack, or reject `localhost` up front and require
`127.0.0.1` in the redirect URI with a clear message.

### P2-4: Refresh token is stored but unusable

The OAuth2 flow stores `X_GW_OAUTH2_REFRESH_TOKEN` and `X_GW_OAUTH2_EXPIRES_AT`
in kinko, but there is no `auth oauth2 refresh` command and no automatic
refresh anywhere in the executor. X user-context access tokens expire in about
two hours, so every expiry forces a full browser round trip even though the
material for a silent refresh is already persisted. This is the largest
usability gap for the primary agent-driven use case. Add a refresh subcommand
(and optionally auto-refresh-on-401 when refresh material is available).

### P2-5: 401 responses never map to `AUTH_EXPIRED`/`AUTH_REVOKED`; 409 never maps to `CONFLICT`

`mapHTTPError` (`Sources/XGatewayCore/XGatewayLiveExecutor.swift:749`) maps
all 401s to `authInvalid` and has no 409 branch, so the `authExpired`,
`authRevoked`, and `conflict` error codes (and their distinct exit codes 4/7)
are dead. CLAUDE.md explicitly requires distinguishing "expired token, revoked
credential". The upstream 401 body usually carries enough signal
(`error_description`, `title`) to classify expiry vs. invalidity; combined
with the stored `X_GW_OAUTH2_EXPIRES_AT` the client could report
`AUTH_EXPIRED` with a "run auth oauth2 refresh" remediation.

### P2-6: HTTP 400 is reported as a credentials problem

The `mapHTTPError` fallback labels every unclassified status - including 400
validation errors from X - with likely causes "API credentials are missing
required access" and remediations about the developer portal. A malformed
search query or an invalid `start_time` therefore produces an auth-flavored
diagnostic, violating the "explain what failed and why" requirement. Add a
400-specific branch mapped to `VALIDATION_ERROR`/`upstream validation`
classification that surfaces the upstream `errors[].message` content.

### P2-7: Rate-limit handling ignores upstream reset headers

On 429 the client retries after generic exponential backoff and the error
payload does not include `x-rate-limit-reset`, `x-rate-limit-remaining`, or
any wait duration. The retry can fire long before the window resets (wasting a
retry) and the final error gives the agent no concrete "retry after N seconds"
remediation, despite rate limiting being called out in CLAUDE.md as a case
needing concrete recovery actions. Read the rate-limit headers, sleep until
reset when it fits inside the configured retry budget, and embed the reset
time in the error payload.

### P2-8: `command.md` "Current CLI" section is wrong, and `--help`/`--version` fail

`command.md` documents `x-gateway-reader [--help] [--version]` as the CLI.
Neither flag exists: both are rejected by `assertAllowedFlags` with
"Unknown flag --help" (exit 2). Conversely, the actual rich command surface
(`auth`, `graphql`, `stream`, `capabilities`, `health`, `version`) is not
listed in that section. Also, the design skill says `command.md` should record
exit codes; the exit-code table in `mapErrorToExitCode` is undocumented.
Update the spec and consider implementing `--help`/`--version` as aliases for
usage/`version` since agents commonly probe them.

### P2-9: Dead `requiresOAuth1` path with misleading attachment error

`SupportedGraphQLOperation.requiresOAuth1`
(`Sources/XGatewayCore/XGatewayGraphQLOperationParsing.swift:252`) is
hardcoded `false`, so the elaborate error in
`requireAuthorization` ("attachments requires complete OAuth1 credentials...")
is unreachable. Meanwhile `prefersBearerAuthorization` routes attachment posts
to bearer (OAuth2 chunked upload). Either remove the dead branch and its error
copy, or restore the intended semantics; as written, a reader of the auth code
gets an incorrect picture of attachment requirements.

### P2-10: Media processing polls can time out on normal videos

Both `ensureTweetOAuth2MediaProcessingComplete` and the DM variant poll at
most 10 times with waits clamped to 5 seconds (about 50 seconds total). X
video processing regularly exceeds this for larger files; the result is a
retryable "processing did not finish" error whose retry re-uploads the entire
file from scratch. Honor `check_after_secs` without the 5-second clamp and
budget the loop against a media-specific timeout, and on timeout report the
`media_id` so a follow-up `mediaUploadStatus` query can resume rather than
re-upload.

### P2-11: Upload/download requests share the 30-second default timeout

`URLSessionConfiguration.timeoutIntervalForResource` is set to the same
`timeout-ms` (default 30,000) used for small JSON calls. A 512 MB video append
or a large media download cannot complete in 30 seconds on most links, so
attachment workflows fail unless the user knows to raise `--timeout-ms`
globally (which also loosens it for everything else). Introduce a separate
transfer timeout (or scale by payload size) for multipart/append/download
requests.

### P2-12: Stream collector retains the whole stream in memory

`XGatewayStreamCollector` (`Sources/XGatewayCore/XGatewayStreamExecutor.swift:134`)
appends every chunk to `rawBody` unconditionally; `rawBody` is only needed for
error diagnostics when the status is non-2xx. A long `--duration-seconds`
session with high event volume duplicates every byte of the stream in a Swift
`String` in addition to the parsed `events` array (which is also unbounded up
to `maxEvents`, capped at 1,000 - acceptable). Only accumulate `rawBody` when
the response status is known to be non-2xx.

Additionally, `--reconnect true` is silently capped by `transport.retryCount`
(default 2) reconnect attempts; the summary reports `reconnects` but the cap
is not documented in `command.md` and is surprising for a flag that reads as
"keep the stream alive".

### P2-13: Media auto-download is triggered by an environment variable alone

Post projection downloads media whenever `downloadMedia` (default `true`) and
a media root dir are both set - and the media root can come from the global
`X_GW_MEDIA_ROOT_DIR` environment variable. An agent environment that exports
that variable turns every read of every media post into synchronous downloads
via `Data(contentsOf:)` (`XGatewayResponseProjector.swift:404`), which has no
timeout, no retry policy, ignores `TransportSettings`, and runs inside the
projection layer (network I/O in the projector is also a layering violation -
see P3-1). Consider defaulting `downloadMedia` to `false`, or requiring the
per-query `mediaRootDir` argument for downloads and treating the env var as a
default location only, and route downloads through the transport with its
timeout/retry configuration.

### P2-14: Default OAuth2 scope request is all known scopes including writes

`XGatewayOAuth2.parseScopes` returns `allKnownScopes` (every read and write
scope, DMs included) when `--scopes` is omitted. A user authorizing the
read-only workflow grants `tweet.write`, `dm.write`, `list.write`, etc. by
default. Least-privilege default (for example read scopes plus
`offline.access`) with `--scopes all` as the explicit opt-in would match the
reader/writer separation philosophy of the product.

### P2-15: `task test`/`task ci` do not run the XCTest suite

`Tests/XGatewayCoreTests` (469 lines, including the valuable
`CapabilityCoverageTests` registry-alignment check) is only exercised by
`swift test`, which no Taskfile target invokes. `task test` runs the separate
smoke executable and `task ci` runs build plus smoke. CLAUDE.md instructs
running `task test` after modifications, so the XCTest suite can silently rot.
Add `swift test` to `ci` (and/or `test`), or fold the smoke executable into
XCTest to have one harness (see P3-6).

## P3 Findings

### P3-1: Layering: network I/O inside the response projector

`materializeMediaAsset` performs downloads from within
`XGatewayResponseProjector`, which otherwise is a pure payload-shaping layer.
Moving materialization into the executor (after projection) would keep the
projector pure, make it unit-testable without network, and let downloads share
transport settings, retry, and tracing.

### P3-2: Blocking synchronous transport built on semaphores

Every request creates a fresh `URLSession`, runs a data task, and blocks on a
`DispatchSemaphore` (`performSingleRequest`, `performSingleBinaryDownloadRequest`,
OAuth2 `performSynchronousRequest`). Consequences:

- No connection reuse: each request pays TLS setup; `followingTimeline` fanout
  (up to 100 sequential requests) and reply hydration multiply this cost.
- The calling thread blocks, which is hostile to any future library embedder
  (P2-1) and to Swift concurrency adoption.
- The manual "semaphore timeout = timeout-ms + 1s" pattern duplicates
  URLSession's own timeout and is repeated in three places.

Recommended direction: one shared `URLSession` per executor, and an
async/await core with a small synchronous bridge for the CLI.

### P3-3: Repeated `GET /2/users/me` lookups

`authenticatedUserId` is called per operation with no caching, so `repostPost`,
`likePost`, `bookmarks`, `homeTimeline`, and `followingTimeline` each spend an
extra request (and rate-limit budget) resolving the same user id. Cache the id
per executor instance (the executor is constructed per command invocation, so
a simple `lazy`/memo is safe).

### P3-4: Three parallel private helper sets in projector files

`XGatewayResponseProjector.swift`, `XGatewayMCPParityProjectors.swift`
(`mcp*`-prefixed), and `XGatewayExtendedParityProjectors.swift` each define
private `object`/`dataObject`/`stringValue`/`intValue`/`boolValue`/
`copyString`/`pageInfo` variants with identical semantics. The prefix naming
exists only to avoid collisions between the private copies. Consolidate into
one internal utility namespace; this also removes drift risk (the `boolValue`
string-truthiness sets already have to be kept mentally in sync).

### P3-5: Duplicated chunked media upload implementations

`XGatewayTweetAttachments.swift` (OAuth2 and OAuth1 paths) and
`XGatewayDirectMessageAttachments.swift` implement the same
initialize/append/finalize/poll loop with different chunk sizes, category
mappers, and near-identical `extract*MediaId`/`*ProcessingInfo`/polling code.
A single parameterized upload engine (category, chunk size, endpoint family)
would remove roughly 300 duplicated lines and one class of bugfix divergence
(for example, the DM poll reads `check_after_secs` as `Int` only, while the
tweet poll accepts Int/Double/String via `mediaProcessingIntValue`).

### P3-6: Two test harnesses; smoke tests reimplement XCTest

`XGatewaySwiftSmokeTests` is a 2,000+ line executable with hand-rolled
`assert`. It predates or parallels the XCTest target. Keeping both means two
places to add coverage and two invocation paths (`swift run ...` vs
`swift test`). Prefer migrating smoke coverage into XCTest (it already runs
the CLI in-process) and keep at most a thin release-binary smoke script.

### P3-7: Four registries must be kept manually aligned

A public field must be consistently present in: (1) the hand-written schema
string in `XGatewayGraphQLSchema.swift`, (2) the
`supportedQuery/MutationGraphQLFields` arrays, (3) the parser dispatch
(`parse*Operation` chains), (4) the executor dispatch switches, and (5)
`capabilityRows()`. `architecture.md` itself calls drift here "an architecture
bug". `CapabilityCoverageTests` checks capability-vs-schema and
capability-vs-routing but not schema-vs-parser (a field in the schema string
with no parser branch, or vice versa, passes). Options: generate the schema
string and the field arrays from the same definition tables the OpenAPI-parity
layer already uses (that layer shows the table-driven pattern works well), or
extend the coverage test to diff schema field names against
`supportedQueryGraphQLFields + supportedMutationGraphQLFields`.

### P3-8: Version string duplicated in three places

`0.1.3` is hardcoded in `XGatewayCore.swift:219`, the smoke-test
`formulaSmokeVersion`, and the `VERSION` file. Release bumps must touch all
three. Generate the Swift constant from `VERSION` at build time (a small
plugin or a Taskfile-driven codegen step), or at least add a smoke check that
compares the CLI `version` output with `VERSION`.

### P3-9: Host usage is split across api.twitter.com / api.x.com / upload.twitter.com

`xAPIURL` uses `api.twitter.com` while `xUsageAPIURL` (usage, media v2,
OpenAPI parity operations) uses `api.x.com`, and OAuth1 media uses
`upload.twitter.com`. All v2 endpoints are served on `api.x.com` today;
standardizing (with one documented exception list if any legacy endpoint
requires the old host) would reduce confusion and future breakage if the
twitter.com aliases degrade. Also consider a `User-Agent: x-gateway/<version>`
header for supportability, and sending `traceId` as a request header so the
trace id in error payloads correlates with anything X-side.

### P3-10: Minor CLI/UX issues

- `usage()` returns exit 0 on stdout when invoked with no arguments; agents
  treating exit 0 as success may mis-parse the usage text as a result.
  Conventional behavior is usage on stderr with a non-zero exit for "no
  command".
- Duplicate flags silently last-wins (`parsed.flags[key]?.last`).
- `unsupported` and `internalError` share exit code 10; separating them would
  let callers distinguish "will never work" from "bug".
- The writer invokes mutations via `graphql query '<mutation>'`; the noun
  "query" for a mutation-only surface reads oddly. A `graphql exec` alias
  would be clearer without breaking the existing form.
- Secrets are accepted via CLI flags (`--token`, `--consumer-secret`, ...),
  which leak into shell history and process listings. Documenting the
  env/kinko-first guidance in `command.md`, and possibly warning on stderr
  when secrets arrive via argv, would be a cheap hardening step.
- `updateList` with no optional arguments sends an empty-object PUT; require
  at least one changed field at validation time.

### P3-11: GraphQL variables unsupported forces string interpolation

Because `$variables` are rejected, callers must interpolate user text directly
into the document. Text containing `"` or `\` must be pre-escaped by the
caller exactly as `parseStringLiteral` expects; agents frequently get this
wrong, and the failure is a generic validation error. Supporting a
`--variables '<json>'` flag (JSON object bound to `$name` references) would
remove the sharpest edge for programmatic callers without needing full
GraphQL variable-definition typing (`design-public-graphql-contract.md`
already anticipates the root-selection parsing consequences).

### P3-12: Reply hydration limits and recency window are under-documented

`Post.replies` is implemented as `search/recent` with
`in_reply_to_tweet_id:<id>` (`XGatewayLiveExecutor.swift:378`), so:

- Replies older than the 7-day recent-search window are silently absent.
- The 25-lookup budget (`maxReplyExpansions`) aborts the entire request with a
  validation error midway through a page rather than degrading (for example,
  returning the posts hydrated so far plus a truncation marker).

Both behaviors are legitimate engineering choices but should be stated in
`design-post-replies-query.md`/`command.md` so agents do not misinterpret an
empty `replies` page as "no replies exist".

### P3-13: Repository hygiene: leftover TypeScript scaffolding

`src/lib.ts`, `src/main.ts`, `src/lib.test.ts`, `package.json`, `bunfig.toml`,
`tsconfig.json`, and `biome.json` are tracked in git but the product is now a
Swift package (the npm-release skill may still depend on some of these -
verify before removal). `Tests/AppCoreTests/` is an empty tracked directory.
Stale scaffolding misleads new contributors and tooling (for example, the
claude-api skill's provider grep would match `bunfig`/`package.json` context).
Decide whether the npm distribution is still a supported surface; if yes,
document it in `architecture.md`; if no, remove the files.

### P3-14: Sequential fanout in `followingTimeline` has no partial-result story

The fanout (`XGatewayLiveTimelineAdapters.swift:4`) issues up to
1 + `maxUsers` sequential requests. A 429 on user #24 of 25 discards all
fetched data and returns only the rate-limit error. Given the endpoint's
"bounded aggregate" framing in `architecture.md`, returning partial results
with a `pageInfo`-level warning (or at least documenting the all-or-nothing
behavior) would make the command more usable under the tight X rate limits
that this exact fanout pattern tends to hit.

## Positive Observations

Recorded so future refactors preserve them deliberately:

- The `XGatewayErrorPayload` shape (code, summary, details, likelyCauses,
  remediations, classification, retryable, traceId) is consistently applied
  and is exactly what the agent-first product direction calls for.
- The OpenAPI-parity layer's table-driven definition style
  (`XGatewayOpenAPIParityOperationParsing.swift`) is the strongest structural
  pattern in the codebase and is the natural template for fixing P3-7.
- OAuth1 signing matches the RFC 5849 test vectors (verified by smoke
  fixtures) and correctly excludes multipart bodies from the signature base.
- The hand-rolled GraphQL scanner consistently handles strings, escapes, and
  comments across all extraction helpers, and hostile inputs (unterminated
  literals, fragments, directives, multiple operations) are rejected with
  specific messages.
- Reader/writer surface separation is enforced at operation-classification
  time, not just by binary naming, and is covered by smoke tests.
- OAuth2 PKCE flow validates `state`, never prints token values, and
  loopback-restricts the redirect target.

## Suggested Remediation Order

1. P1-1 (mutation retry duplication) and P1-2 (owner metrics) - correctness
   of writes and reads respectively.
2. P1-3/P1-4/P1-6 (silently ignored inputs) - small fixes, large trust gain.
3. P2-4 (OAuth2 refresh) and P2-5/P2-6/P2-7 (error taxonomy) - the largest
   agent-experience gaps.
4. P2-1 (library API) together with P3-2 (async transport) - one design
   effort.
5. Registry/version/test consolidation (P3-6/P3-7/P3-8) - guardrails that
   make all later changes safer.

Each numbered finding is sized to become one implementation-plan task under
`impl-plans/active/` when scheduled.
