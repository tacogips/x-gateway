# Public metrics for ordinary reads

Issue: https://github.com/tacogips/x-gateway/issues/5

Use public metrics by default in shared post request encoding. Preserve explicit private-metric opt-in, public metric projection, pagination and media/reference expansions. Validate exact decoded request fields for liked/list pages and single/batch lookups without network calls. Run full Swift tests, smoke/build and lint; release 0.1.11 and integrate its public revision into Riela only after request gates and caller validation.

Official constraint: https://docs.x.com/x-api/fundamentals/metrics restricts private metrics to eligible owned posts within 30 days. This is a confirmed request-shape defect; it does not by itself prove the cause of a caller HTTP failure.

Verification: 30 XCTest tests passed, full `mise run ci` production build and smoke tests passed, SwiftLint reports zero violations. Nix validation is unavailable: this Swift checkout has no flake.nix and the host has no nix executable; no Nix artifact is claimed. Final reader image and coordinated max-5 caller validation precede release tagging.

The corrected public-field image passed guard/schema/adversarial tests, but the single coordinated caller max-5 read still returned HTTP403. Do not claim the metrics change resolved that denial. Issue https://github.com/tacogips/x-gateway/issues/6 adds finite problem/reason diagnostics and bounded numeric error codes, propagated independently through Riela's privacy allowlist; raw provider text remains excluded from that boundary. Validate secret-bearing unknown inputs and preserve fields through token annotation before the next coordinated request.

Finite diagnostics validation: 33 XCTest tests, production build/smoke and SwiftLint all pass; Riela independent boundary regressions pass. No raw text is inferred or copied into the new fields. Source/image review and coordinated provider-reason check remain before release tagging.

Completed: v0.1.11 is public at revision9f0c0d002efa4e061d6ed8795dbe5eab89f7432c with four verified assets. Both reader/writer archives run on arm64/x64; public GitHub asset digests match. Tap commit03522fd63a865dd78885654f69df3597fbf4598f passed strict audits, fetch, upgrade and both brew tests. Metadata workflow39122094232 succeeded; public main and immutablee4a5f6154cd2dd6b160a2d0a1644ed214600e8f7 metadata report0.1.11 and exact formula hashes.

The coordinated diagnostic image passed all guard/schema/frame/isolation/log checks. Caller max-5 request still returned HTTP403 with unknown finite problem/reason and no numeric provider code. The denial cause remains unconfirmed; no scope, enrollment or billing conclusion is claimed. Further provider requests stopped. These verified SDK fixes are released independently of that account access condition.
