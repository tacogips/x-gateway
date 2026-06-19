# x-gateway Swift Media Download Baseline Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/command.md#swift-split-commands
**Created**: 2026-06-19
**Last Updated**: 2026-06-19

## Design Document Reference

This plan ports the Swift local media materialization baseline for read
projections. Swift read fields already exposed media URLs; this slice adds the
TypeScript contract controls for `mediaRootDir`, `downloadMedia`, and
`forceDownload`.

Out of scope:
- live credential-specific verification of every X media variant shape

## Modules

### 1. Public Read Options

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftPostReadOptions = {
  mediaRootDir?: string;
  downloadMedia?: boolean;
  forceDownload?: boolean;
  includePromoted?: boolean;
};
```

**Status**: Completed

**Checklist**:
- [x] Add public Swift read-options type for projector callers
- [x] Parse read media controls from GraphQL fields
- [x] Apply `X_GW_MEDIA_ROOT_DIR` as the default root when no field argument is set

### 2. Media Materialization

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftMediaMaterialization = "source-only" | "local-file";
```

**Status**: Completed

**Checklist**:
- [x] Build deterministic media file paths under `mediaRootDir/<post-id>/`
- [x] Reuse existing local files unless `forceDownload` is true
- [x] Download missing or forced media from supported http/https source URLs
- [x] Return remediation-oriented errors for invalid or failed media downloads

### 3. Smoke Coverage and Documentation

#### Sources/XGatewaySwiftSmokeTests/main.swift

**Status**: Completed

**Checklist**:
- [x] Verify schema exposure for media read controls
- [x] Verify existing local file reuse without network access
- [x] Verify `downloadMedia: false` keeps media source-only
- [x] Update public README and design specs

## Module Status

| Module | File Path | Status | Tests |
|--------|-----------|--------|-------|
| Public read options | `Sources/XGatewayCore/XGatewayCore.swift` | Completed | Covered |
| Media materialization | `Sources/XGatewayCore/XGatewayCore.swift` | Completed | Covered |
| Smoke coverage and documentation | `Sources/XGatewaySwiftSmokeTests/main.swift`, `README.md`, `design-docs/specs/architecture.md`, `design-docs/specs/command.md` | Completed | Covered |

## Dependencies

| Feature | Depends On | Status |
|---------|------------|--------|
| TASK-001: Public read options | Swift projection parity baseline | Completed |
| TASK-002: Media materialization | TASK-001 | Completed |
| TASK-003: Smoke coverage and documentation | TASK-002 | Completed |

## Tasks

### TASK-001: Public Read Options

**Status**: Completed
**Parallelizable**: Yes
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`
**Dependencies**: x-gateway-swift-projection-parity-baseline:TASK-001

**Completion Criteria**:
- [x] Swift schema advertises `mediaRootDir`, `downloadMedia`, and `forceDownload`
- [x] Swift parser accepts media read controls on top-level read fields
- [x] Public projector callers can pass equivalent options directly

### TASK-002: Media Materialization

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`
**Dependencies**: TASK-001

**Completion Criteria**:
- [x] Existing files are reused by default
- [x] `forceDownload` refreshes files when requested
- [x] `downloadMedia: false` suppresses local materialization
- [x] Download failures return structured x-gateway errors

### TASK-003: Smoke Coverage and Documentation

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewaySwiftSmokeTests/main.swift`, `README.md`, `design-docs/specs/architecture.md`, `design-docs/specs/command.md`
**Dependencies**: TASK-002

**Completion Criteria**:
- [x] Swift smoke tests cover media control schema and offline local-file reuse
- [x] README no longer lists Swift media download as pending
- [x] Design docs describe the current Swift media behavior

## Completion Criteria

- [x] Swift read schema and parser support media materialization controls
- [x] Swift projector materializes media under `mediaRootDir/<post-id>/`
- [x] Swift smoke tests verify local-file reuse and source-only behavior
- [x] Public docs and plan tracking reflect the completed slice

## Progress Log

### Session: 2026-06-19 17:05
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None for this media-download slice.
**Notes**: Added `XGatewayPostReadOptions`, GraphQL media read option parsing, local media materialization with existing-file reuse, offline smoke coverage, and documentation updates. Nested `Post.replies(...)` execution was completed by `x-gateway-swift-nested-replies-baseline`.
