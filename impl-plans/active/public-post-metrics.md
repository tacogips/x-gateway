# Public metrics for ordinary reads

Issue: https://github.com/tacogips/x-gateway/issues/5

Use public metrics by default in shared post request encoding. Preserve explicit private-metric opt-in, public metric projection, pagination and media/reference expansions. Validate exact decoded request fields for liked/list pages and single/batch lookups without network calls. Run full Swift tests, smoke/build and lint; release 0.1.11 and integrate its public revision into Riela only after request gates and caller validation.

Official constraint: https://docs.x.com/x-api/fundamentals/metrics restricts private metrics to eligible owned posts within 30 days. This is a confirmed request-shape defect; it does not by itself prove the cause of a caller HTTP failure.

Verification: 30 XCTest tests passed, full `mise run ci` production build and smoke tests passed, SwiftLint reports zero violations. Nix validation is unavailable: this Swift checkout has no flake.nix and the host has no nix executable; no Nix artifact is claimed. Final reader image and coordinated max-5 caller validation precede release tagging.
