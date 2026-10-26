# swift-crypto 5.x Dependency Upgrade

**Status**: Ready
**Plan ID**: `swift-crypto-5-dependency`
**Wave**: 1 (no dependencies; runs in parallel with `version-bump-0-1-27`)
**Design Reference**: `design-docs/specs/architecture.md#third-party-dependency-baseline`
**Issue**: workflowInput `x-gateway: move to swift-crypto 5.x` (no remote issue number)

## Purpose

Riela pins `x-gateway` by `exact:` tag and needs one swift-crypto 5.x version
across its whole dependency graph. Today `Package.swift:29` requires
`"3.0.0"..<"5.0.0"` and `Package.resolved` pins swift-crypto 4.5.2 (plus
swift-asn1 1.7.1). This plan moves the requirement to `from: "5.0.3"`, re-pins
the lockfile to 5.x, and fixes only the compile errors or deprecations that
swift-crypto 5 introduces. Hashing and signing output must not change.

## Non-Goals

- Do not bump `VERSION` or the version constant in `Sources/XGatewayCore/XGatewayCore.swift`. Plan `version-bump-0-1-27` owns those.
- Do not commit, push, or tag. Finalization does that serially after review.
- Do not add `swift-asn1` or any other package as a direct dependency.
- Do not change `swift-tools-version: 5.8` or `.macOS(.v13)` unless the blocker or finding rules below require it.
- Do not add crypto wrapper types, protocols, or helper layers.
- Do not touch the test or smoke-test oracle files listed under Invariants.
- Do not edit `impl-plans/README.md`, `impl-plans/PROGRESS.json`, the Homebrew/Nix/npm packaging files, or `mise.toml`.

## Deliverables

- [ ] `Package.swift`: the swift-crypto requirement is exactly `.package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.3")`.
- [ ] `Package.resolved`: swift-crypto pin `version` is 5.x with a value of at least `5.0.3`. swift-asn1 changes only if SwiftPM changes it.
- [ ] Compile fixes in the crypto call sites, only if `swift build` or `swift test` fails or warns because of swift-crypto 5:
  - `Sources/XGatewayCore/OAuth1.swift`: `XGatewayOAuth1Signer.hmacSHA1Base64(message:key:)`, which uses `SymmetricKey(data:)` and `HMAC<Insecure.SHA1>.authenticationCode(for:using:)`
  - `Sources/XGatewayCore/XGatewayOAuth2.swift`: `XGatewayOAuth2.codeChallenge(for:)`, which uses `SHA256.hash(data:)`
  - `Sources/XGatewayCore/XGatewayResourceUsage.swift`: line ~85 `SHA256.hash(data:)` with lowercase `%02x` hex join
- [ ] Recorded evidence of the resolved swift-crypto 5.x manifest facts (see TASK-002).

## Invariants

- Public signatures stay unchanged: `XGatewayOAuth1Signer.hmacSHA1Base64(message: String, key: String) -> String` and `XGatewayOAuth2.codeChallenge(for: String) -> String`.
- Keep the import split. `OAuth1.swift:2-6` and `XGatewayOAuth2.swift:2-6` keep `#if canImport(CryptoKit) import CryptoKit #else import Crypto #endif`. `XGatewayResourceUsage.swift:2` keeps the unconditional `import Crypto`.
- The following byte-for-byte oracles must pass and must NOT be edited:
  - `Tests/XGatewayCoreTests/XGatewayCoreTests.swift:76-84` (HMAC-SHA1 vector and PKCE `E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM`)
  - `Sources/XGatewaySwiftSmokeTests/main.swift:73-101` (HMAC `3nybhbi3iqa8ino29wqQcBydtNk=` and header signature `tR3%2BTy81lMeYAr%2FFid0kMTYa%2FWM%3D`)
  - `Sources/XGatewaySwiftSmokeTests/OAuth2SmokeTests.swift:7`
- The resource-usage hash stays lowercase hex of SHA256 over `"<kind.rawValue>:<id>"` UTF-8.

## Tasks

### TASK-001: Change the requirement and re-resolve

**Parallelizable**: Yes (wave 1)

1. Fresh-read `Package.swift` and record `shasum -a 256 Package.swift Package.resolved` as the pre-edit snapshot.
2. Replace line 29 with `.package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.3")`. Change nothing else in the manifest.
3. Run `swift package update swift-crypto`. Use the targeted update only. Do not run a bare `swift package update`, which would re-pin unrelated packages.
4. Check `grep -A6 '"swift-crypto"' Package.resolved` and confirm `"version" : "5.`.

Pitfalls:
- If resolution fails because something caps swift-crypto below 5, stop and report the exact constraint text as a blocker. Do not loosen the requirement or add overrides. Today the only direct dependency is swift-crypto, so this is not expected.
- Do not hand-edit `Package.resolved`. It must be SwiftPM-generated.

**Completion Criteria**:
- [ ] `grep -n 'swift-crypto' Package.swift` shows exactly `from: "5.0.3"` and no `..<`.
- [ ] `Package.resolved` swift-crypto `version` matches `^5\.` and is at least 5.0.3.
- [ ] `git diff --stat Package.swift` shows a 1-line change.

### TASK-002: Record the resolved 5.x manifest facts

**Parallelizable**: No (depends on TASK-001)

Read `.build/checkouts/swift-crypto/Package.swift` and record the following in this plan's Progress Log:
- its `swift-tools-version`
- any `platforms:` declaration
- its swift-asn1 requirement

Apply the design's rules:
- If the local toolchain is too old for the 5.x tools-version, SwiftPM errors at resolve or build time. Report a blocker and stop. Do not install another toolchain.
- If SwiftPM rejects the root `swift-tools-version: 5.8`, raise it only to the minimum accepted value and record a finding. Do not do this preemptively.
- If 5.x declares a macOS floor above 13 that makes the build fail, report a blocker that needs a maintainer decision. Do not edit `.macOS(.v13)`.

Also record `swift --version` output.

**Completion Criteria**:
- [ ] The Progress Log contains swift-crypto 5.x tools-version, platforms (or "none"), swift-asn1 requirement, and `swift --version`.

### TASK-003: Fix swift-crypto 5 compile errors or deprecations (only if any)

**Parallelizable**: No (depends on TASK-001)

Run `swift build 2>&1 | tee <log>`. Edit the three call-site files only for errors or deprecation warnings that come from the swift-crypto 5 API. Use the smallest replacement API that produces identical bytes. For example, if an initializer is renamed, call the new name. Do not restructure the code.

Pitfalls:
- Do not "fix" a failing oracle by changing its expected string.
- Do not switch HMAC-SHA1 to another algorithm, and do not change base64 or hex encoding.
- Deprecations in unrelated (non-crypto) code are out of scope. Do not touch them.
- On macOS, OAuth1 and OAuth2 compile the CryptoKit branch, so the `import Crypto` branch is not compiled there. Do not edit the `#else` branch speculatively. If it is left unverified, record a Linux-build verification gap.

**Completion Criteria**:
- [ ] `swift build` exits 0.
- [ ] `swift build 2>&1 | grep -i 'deprecat' | grep -i -E 'crypto|HMAC|SHA|SymmetricKey'` produces no output.
- [ ] Either no source file changed, or each changed line is justified in the Progress Log by the exact compiler message.

### TASK-004: Verify outputs unchanged

**Parallelizable**: No (depends on TASK-003)

Test cases (existing tests; add none):
- The `hmacSHA1Base64` vector in XGatewayCoreTests passes with the unchanged expected value.
- RFC 7636 verifier `dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk` gives challenge `E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM`.
- The smoke OAuth1 header contains `oauth_signature="tR3%2BTy81lMeYAr%2FFid0kMTYa%2FWM%3D"`.

**Completion Criteria**:
- [ ] `swift test` exits 0, with the log path recorded.
- [ ] `mise run test` exits 0, with the log path recorded.
- [ ] `git diff --exit-code -- Tests Sources/XGatewaySwiftSmokeTests` exits 0.

## Verification Commands (scoped to this plan)

Run serially. Never run them concurrently with another `swift` command in this working directory, because SwiftPM locks `.build`. Write logs under `.build/riela-logs/` and record each log path and exit status in the Progress Log.

| Command | Must establish |
|---|---|
| `swift package update swift-crypto` | exit 0; lockfile re-pinned |
| `grep -A6 '"swift-crypto"' Package.resolved` | `"version" : "5.x.y"` with a value of at least 5.0.3 |
| `swift build` | exit 0; no crypto deprecation warnings |
| `swift test` | exit 0; the full XGatewayCoreTests suite passes |
| `mise run test` | exit 0; smoke tests pass |
| `git diff --exit-code -- Tests Sources/XGatewaySwiftSmokeTests` | exit 0; oracles untouched |

`mise run lint` (swiftlint) is a workspace-wide gate and runs at integration and reconcile time, not here.

## Concurrency and Drift Rules

- Before every edit, fresh-read the target file and record its sha256. After the edit, record the sha256 again.
- If a file in this plan's writePaths changed between your read and your write without your involvement, stop and report drift. Do not overwrite.
- Do not run any git write operation (add, commit, stash, checkout, reset).

## Progress Log

- 2026-10-27: Plan created from the accepted design (Step 3 accepted, no findings).
