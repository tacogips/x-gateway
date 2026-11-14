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
