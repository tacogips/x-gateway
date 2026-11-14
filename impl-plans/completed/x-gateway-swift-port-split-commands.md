# x-gateway Swift Port Split Commands Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/architecture.md#swift-port-architecture
**Created**: 2026-06-19
**Last Updated**: 2026-06-19

## Design Document Reference

This plan implements the first Swift migration slice from the Swift Port
Architecture section. Scope is limited to introducing the Swift package,
separate read/write executable products, shared CLI/config/error primitives,
install/build tasks for each command, and the first bearer-token live transport
baseline for `accountMe`, `post`, `searchPosts`, `userTimeline`, `createPost`,
`apiUsage`, `homeTimeline`, `followingTimeline`, `mentionsTimeline`,
`deletePost`, `replyToPost`, `quotePost`, `repostPost`, and `unrepostPost`.
Attachment upload, OAuth1 signing, media download, nested referenced-post/reply
hydration, and exact TypeScript projection parity were not included in this
first slice. The follow-up OAuth1 signing baseline is tracked in
`completed/x-gateway-swift-oauth1-signing-baseline.md`.

## Modules

### 1. Swift Package Products

#### Package.swift

```typescript
type SwiftProduct = "XGatewayCore" | "x-gateway-reader" | "x-gateway-writer";
```

**Status**: Completed

**Checklist**:
- [x] Define library product
- [x] Define read executable product
- [x] Define write executable product
- [x] Define test target

### 2. Core CLI Library

#### Sources/XGatewayCore/*.swift

```typescript
type XGatewaySurface = "read" | "write";

interface XGatewayCommandResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}
```

**Status**: Completed

**Checklist**:
- [x] Parse global flags and positionals
- [x] Preserve success/error JSON envelopes
- [x] Resolve auth/config from environment
- [x] Classify GraphQL query vs mutation
- [x] Enforce read/write command separation

### 3. Executable Entrypoints

#### Sources/XGatewayRead/main.swift, Sources/XGatewayWrite/main.swift

```typescript
type SwiftExecutable = "x-gateway-reader" | "x-gateway-writer";
```

**Status**: Completed

**Checklist**:
- [x] Wire read command to read-only surface
- [x] Wire write command to write-only surface
- [x] Exit with command result status

### 4. Swift Smoke Tests

#### Sources/XGatewaySwiftSmokeTests/main.swift

```typescript
interface SwiftCliTestCase {
  surface: XGatewaySurface;
  arguments: readonly string[];
  expectedExitCode: number;
}
```

**Status**: Completed

**Checklist**:
- [x] Test operation classification for read GraphQL documents
- [x] Test read command rejects mutations
- [x] Test write command rejects read queries
- [x] Test JSON error envelope shape

### 5. Install Tasks and Documentation

#### Taskfile.yml, README.md

```typescript
type InstallTask = "swift:install-reader" | "swift:install-writer";
```

**Status**: Completed

**Checklist**:
- [x] Add separate read install task
- [x] Add separate write install task
- [x] Document SwiftPM product build/install commands

## Module Status

| Module | File Path | Status | Tests |
|--------|-----------|--------|-------|
| Swift Package Products | `Package.swift` | Completed | - |
| Core CLI Library | `Sources/XGatewayCore/*.swift` | Completed | Covered |
| Executable Entrypoints | `Sources/XGatewayRead/main.swift`, `Sources/XGatewayWrite/main.swift` | Completed | Covered |
| Swift Smoke Tests | `Sources/XGatewaySwiftSmokeTests/main.swift` | Completed | Covered |
| Install Tasks and Documentation | `Taskfile.yml`, `README.md` | Completed | - |

## Dependencies

| Feature | Depends On | Status |
|---------|------------|--------|
| TASK-001: Swift package products | None | Completed |
| TASK-002: Core CLI library | TASK-001 | Completed |
| TASK-003: Executable entrypoints | TASK-002 | Completed |
| TASK-004: Swift tests | TASK-002, TASK-003 | Completed |
| TASK-005: Install docs/tasks | TASK-001, TASK-003 | Completed |

## Tasks

### TASK-001: Swift Package Products

**Status**: Completed
**Parallelizable**: Yes
**Deliverables**: `Package.swift`
**Dependencies**: None

**Completion Criteria**:
- [x] Package has library, read executable, write executable, and test products/targets

### TASK-002: Core CLI Library

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewayCore/*.swift`
**Dependencies**: TASK-001

**Completion Criteria**:
- [x] Core library parses arguments and flags
- [x] Core library resolves auth/config from environment
- [x] Core library emits structured success and error output
- [x] Core library enforces read/write GraphQL operation separation

### TASK-003: Executable Entrypoints

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewayRead/main.swift`, `Sources/XGatewayWrite/main.swift`
**Dependencies**: TASK-002

**Completion Criteria**:
- [x] Read executable invokes read surface
- [x] Write executable invokes write surface

### TASK-004: Swift Smoke Tests

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewaySwiftSmokeTests/main.swift`
**Dependencies**: TASK-002, TASK-003

**Completion Criteria**:
- [x] Tests cover operation classification and surface rejection behavior

### TASK-005: Install Docs and Tasks

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Taskfile.yml`, `README.md`
**Dependencies**: TASK-001, TASK-003

**Completion Criteria**:
- [x] Separate read and write install commands are documented
- [x] Separate read and write Taskfile tasks are available

## Completion Criteria

- [x] Swift package files are present
- [x] Read and write executable products can be installed independently
- [x] Tests cover the read/write surface split
- [x] Documentation describes the Swift split-command install path
- [x] Verification commands run or blocked status is documented

## Progress Log

### Session: 2026-06-19 10:45
**Tasks Completed**: None
**Tasks In Progress**: TASK-001, TASK-002, TASK-003, TASK-004, TASK-005
**Blockers**: Local `swift` was not installed directly; subsequent session added Swift to the Nix dev shell.
**Notes**: Riela workflow intake succeeded but did not advance past intake; continued with direct implementation using the same task scope.

### Session: 2026-06-19 11:25
**Tasks Completed**: TASK-001, TASK-002, TASK-003, TASK-004, TASK-005
**Tasks In Progress**: None
**Blockers**: Nix Swift toolchain initially lacked XCTest; smoke tests were migrated to an executable harness.
**Notes**: Added SwiftPM package, read/write executable products, shared core CLI behavior, Swift smoke tests, separate install tasks, and README usage.

### Session: 2026-06-19 12:05
**Tasks Completed**: TASK-001, TASK-002, TASK-003, TASK-004, TASK-005
**Tasks In Progress**: None
**Blockers**: None for this slice.
**Notes**: Added Swift tooling to the Nix shell, verified both Swift command products build, replaced XCTest with an executable smoke harness, and added bearer-token live execution for `accountMe`, `createPost`, and `deletePost`.

### Session: 2026-06-19 12:35
**Tasks Completed**: TASK-002, TASK-004
**Tasks In Progress**: None
**Blockers**: None for this slice.
**Notes**: Expanded Swift bearer-token live execution to `post`, `searchPosts`, `userTimeline`, `replyToPost`, `quotePost`, `repostPost`, and `unrepostPost`; smoke tests now prove each supported route reaches auth validation without credentials.

### Session: 2026-06-19 13:05
**Tasks Completed**: TASK-002, TASK-004
**Tasks In Progress**: None
**Blockers**: None for this slice.
**Notes**: Added Swift bearer-token routes for `apiUsage`, `homeTimeline`, `followingTimeline`, and `mentionsTimeline`; the read command now covers all current top-level project-owned GraphQL query fields at a raw bearer transport baseline.

### Session: 2026-06-19 13:35
**Tasks Completed**: TASK-002, TASK-004
**Tasks In Progress**: None
**Blockers**: None for this slice.
**Notes**: Added Swift response projection helpers for stable account, usage, post, post page, created/deleted post, and repost result shapes; smoke tests now validate projection with offline fixtures.

### Session: 2026-06-19 13:50
**Tasks Completed**: TASK-002, TASK-004, TASK-005
**Tasks In Progress**: None
**Blockers**: None for this slice.
**Notes**: Wired Swift live transport timeout and retry flags into `XGatewayLiveExecutor`, fixed stale unsupported-field remediation, revalidated Swift smoke tests, and verified read/write products install independently.
