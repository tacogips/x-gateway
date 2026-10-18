# Home timeline bounds and pagination

Issue: https://github.com/tacogips/x-gateway/issues/3

Expose the five documented optional bounds/cursor arguments only on homeTimeline. Parse them using existing string validation, forward their snake_case names to the authenticated reverse_chronological endpoint, and preserve response projection and authentication.

1. Add cohesive request options and schema/parser/executor wiring.
2. Test all parameters, omitted compatibility, type rejection, timeline isolation and cursor projection.
3. Run Swift tests, smoke, lint and release quality gates.
4. Publish patch 0.1.9, update both Homebrew formulas, and integrate released SDK/image revision into Riela.

Reference: https://docs.x.com/x-api/users/get-timeline

Implementation and pre-release gates complete: 24 XCTest tests passed, including four focused home timeline tests; mise run ci (production build plus smoke tests) passed; SwiftLint found zero violations. Existing native Riela OAuth1 home timeline read returned five posts. Parent independently reviewed the scoped parameter forwarding and found no blocker. Nix is not configured in this checkout and the nix executable is unavailable; no Nix artifact is claimed.

Release complete: https://github.com/tacogips/x-gateway/releases/tag/v0.1.9 . Source 1ca8380b74e5fc1da02d80bb0e1a46ee43a0765a; all four public assets verified. Both architectures' reader/writer commands passed version/help/schema and checksum checks. Official Riela reader image built from the released revision and passed readonly/no-network schema/version smoke.

Homebrew tap commit 4b998c28368753d04b9a98a205e3371a3892023f; both strict audits, fetches, upgrades and brew tests passed. Metadata workflow 39112290350 succeeded; public main and immutable f7ab470b939a43c44ecbf5022be06958662905ce metadata verified both versions and exact formula hashes.

Current official documentation states home timeline retention is the most recent 3,200 posts or seven days, excluding algorithmic ranking: https://docs.x.com/x-api/posts/timelines/introduction . Exhausting pagination does not promise an unrestricted historical export.
