# Liked post archive support

Correct likedPosts OAuth1 support from current official auth mapping/OpenAPI; preserve bearer fallback. Expose referenced-post identity metadata when expansions are absent, with existing depth limits and no additional requests. Add explicit HTTP status to structured errors so Riela can retain safe diagnostics without provider text.

Validate pure auth selection (mixed credentials, bearer-only, missing), missing/nested reference projection, status preservation through auth diagnostics, Swift tests, CI/smoke, lint and0.1.10 macOS release archives. Build a separately tagged image first to avoid changing frozen Riela0.2.7 verification inputs.
