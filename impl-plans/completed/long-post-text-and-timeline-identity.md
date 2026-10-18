# Long post text and verified home timeline identity

Issue: https://github.com/tacogips/x-gateway/issues/7

Request `note_tweet` through the shared post-field encoder. Prefer nonblank string
`note_tweet.text` in the recursive projector, preserving its whitespace and Unicode
verbatim. Fall back to ordinary `text` for absent or malformed values. This applies
to pages, single/batch lookups and nested originals/quotes without extra requests,
permission changes or a wider reference depth.

Official field reference: https://docs.x.com/x-api/fundamentals/data-dictionary

Allow optional `homeTimeline(userId: ID)` for callers that already verified the
account. Require a quoted nonempty ASCII numeric ID before authentication or any
request. Reuse it only within that operation, retain the default `/2/users/me`
lookup when omitted, and leave authorization to the existing credentials and X.
No credential cache is introduced. The request helper accepts a scoped closure
so tests can record the actual endpoint URLs without contacting X.

Verification: 39 XCTest tests pass, including Unicode long text in root/repost/two
quote levels, malformed-field fallback, post-request fields, and supplied/default/
invalid ID request counts of 1/2/0. SwiftLint reports zero violations. Production
build/smoke and both macOS archives pass; each archived reader/writer reports 0.1.12.
Independent source review found no blockers. Public release verification follows.
Nix validation is unavailable: this checkout has no flake.nix and this host has no
nix executable. No Nix output or live provider validation is claimed.

Released v0.1.12 at f91fae662e45606cfd6847e884e170c02d8e83cd:
https://github.com/tacogips/x-gateway/releases/tag/v0.1.12
All four public assets match their local SHA-256 digests. Both arm64 and x64
archives contain reader/writer executables that report 0.1.12.
Tap commit 70dfb7846be6801861a859401f6574cb5d7b6a47 passed Ruby syntax,
strict audits, fetch, upgrade and both brew tests. Metadata workflow 39126442897
succeeded; public raw reader/writer JSON reports 0.1.12 and hashes matching the
committed formulae. Issue 7 is closed. Riela/container rollout is coordinated
separately; this release performed no provider requests or container operations.
