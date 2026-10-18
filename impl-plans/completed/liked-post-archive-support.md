# Liked post archive support

Correct likedPosts OAuth1 support from current official auth mapping/OpenAPI; preserve bearer fallback. Expose referenced-post identity metadata when expansions are absent, with existing depth limits and no additional requests. Add explicit HTTP status to structured errors so Riela can retain safe diagnostics without provider text.

Validate pure auth selection (mixed credentials, bearer-only, missing), missing/nested reference projection, status preservation through auth diagnostics, Swift tests, CI/smoke, lint and0.1.10 macOS release archives. Build a separately tagged image first to avoid changing frozen Riela0.2.7 verification inputs.

Released v0.1.10 at d7a7cd9947b43dccaec6708c24de35bfa4742396 with four public assets. All28 Swift tests, production/CLI smoke, zero lint violations, both architecture archive checksum/version/help checks passed. Tap94c3fc4 strict audits/fetches/upgrades/tests passed, metadata workflow39113802533 succeeded and public main plus b5006718 metadata versions/formula hashes verified. Nix unavailable (no flake.nix, no executable). Official reader candidate image8a627819 built and readonly/no-network version verified. No external API requests used for this fix; parent performs authorized integration.
