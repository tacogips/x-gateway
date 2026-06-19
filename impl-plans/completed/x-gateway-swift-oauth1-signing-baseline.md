# x-gateway Swift OAuth1 Signing Baseline Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/architecture.md#swift-port-architecture
**Created**: 2026-06-19
**Last Updated**: 2026-06-19

## Design Document Reference

This plan closes the next Swift migration gap after the split read/write
commands: non-usage Swift live requests need OAuth1 request signing so mixed
credential shells do not lose the reviewed OAuth1 path. The slice keeps the
existing bearer-token fallback while making complete OAuth1 credentials the
preferred route for supported operations.

Out of scope:
- Swift media upload
- TypeScript projection parity for nested hydration
- live OAuth1 scope probing beyond configured credential diagnostics

## Modules

### 1. C HMAC-SHA1 Helper

#### Sources/XGatewayCrypto/

```typescript
type OAuth1DigestPrimitive = {
  algorithm: "HMAC-SHA1";
  outputBytes: 20;
};
```

**Status**: Completed

**Checklist**:
- [x] Add SwiftPM C target for digest support
- [x] Expose stable HMAC-SHA1 function to Swift
- [x] Avoid compiler-heavy pure Swift digest expressions

### 2. Swift OAuth1 Signer

#### Sources/XGatewayCore/OAuth1.swift

```typescript
type SwiftOAuth1Signer = {
  signatureBaseString(method: string, url: string): string;
  authorizationHeader(method: string, url: string): string;
};
```

**Status**: Completed

**Checklist**:
- [x] Normalize OAuth1 parameters and request base URL
- [x] Percent-encode parameters according to OAuth1 rules
- [x] Produce RFC 5849-compatible signatures and Authorization headers

### 3. Live Executor Auth Routing

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftAuthRoute = "oauth1-preferred" | "bearer-only-usage" | "bearer-fallback";
```

**Status**: Completed

**Checklist**:
- [x] Resolve OAuth1 credentials from CLI flags and environment variables
- [x] Prefer OAuth1 signing for non-usage live operations
- [x] Keep bearer-only routing for `apiUsage`
- [x] Update auth diagnostics, capability metadata, and public docs

## Module Status

| Module | File Path | Status | Tests |
|--------|-----------|--------|-------|
| C HMAC-SHA1 helper | `Sources/XGatewayCrypto/` | Completed | Covered |
| Swift OAuth1 signer | `Sources/XGatewayCore/OAuth1.swift` | Completed | Covered |
| Auth routing and metadata | `Sources/XGatewayCore/XGatewayCore.swift` | Completed | Covered |

## Dependencies

| Feature | Depends On | Status |
|---------|------------|--------|
| TASK-001: Digest helper | Swift split commands | Completed |
| TASK-002: OAuth1 signer | TASK-001 | Completed |
| TASK-003: Executor routing and docs | TASK-002 | Completed |

## Tasks

### TASK-001: Digest Helper

**Status**: Completed
**Parallelizable**: Yes
**Deliverables**: `Sources/XGatewayCrypto/include/XGatewayCrypto.h`, `Sources/XGatewayCrypto/hmac_sha1.c`, `Package.swift`
**Dependencies**: x-gateway-swift-port-split-commands:TASK-001

**Completion Criteria**:
- [x] SwiftPM builds a C helper target for HMAC-SHA1
- [x] Swift code can obtain a base64 HMAC-SHA1 digest

### TASK-002: OAuth1 Signer

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewayCore/OAuth1.swift`, `Sources/XGatewaySwiftSmokeTests/main.swift`
**Dependencies**: TASK-001

**Completion Criteria**:
- [x] OAuth1 signature base string construction is implemented
- [x] RFC 5849 signature fixture is covered by Swift smoke tests

### TASK-003: Executor Routing and Documentation

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`, `README.md`, `design-docs/specs/architecture.md`, `design-docs/specs/command.md`
**Dependencies**: TASK-002

**Completion Criteria**:
- [x] Non-usage Swift live requests prefer OAuth1 when configured
- [x] `apiUsage` remains bearer-token only
- [x] Auth diagnostics and capability metadata describe the supported routes
- [x] Public documentation reflects the Swift OAuth1 baseline

## Completion Criteria

- [x] Swift has an OAuth1 signing path for supported live operations
- [x] Bearer fallback behavior remains available for the current Swift baseline
- [x] `apiUsage` reports bearer-only requirements
- [x] Swift smoke tests cover signing fixtures and routing metadata

## Progress Log

### Session: 2026-06-19 14:45
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None for this OAuth1 signing slice.
**Notes**: Added a C-backed HMAC-SHA1 primitive, Swift OAuth1 signer, non-usage OAuth1-preferred executor routing, CLI flag-aware auth diagnostics, updated capability statuses, and public documentation for the Swift OAuth1 transport baseline.
