# Home timeline bounds and pagination

Issue: https://github.com/tacogips/x-gateway/issues/3

Expose the five documented optional bounds/cursor arguments only on homeTimeline. Parse them using existing string validation, forward their snake_case names to the authenticated reverse_chronological endpoint, and preserve response projection and authentication.

1. Add cohesive request options and schema/parser/executor wiring.
2. Test all parameters, omitted compatibility, type rejection, timeline isolation and cursor projection.
3. Run Swift tests, smoke, lint and release quality gates.
4. Publish patch 0.1.9, update both Homebrew formulas, and integrate released SDK/image revision into Riela.

Reference: https://docs.x.com/x-api/users/get-timeline

Implementation and pre-release gates complete: 24 XCTest tests passed, including four focused home timeline tests; mise run ci (production build plus smoke tests) passed; SwiftLint found zero violations. Existing native Riela OAuth1 home timeline read returned five posts. Parent independently reviews the patch before publication. Nix is not configured in this checkout and the nix executable is unavailable; no Nix artifact is claimed.
