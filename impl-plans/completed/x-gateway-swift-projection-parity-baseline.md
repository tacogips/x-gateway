# x-gateway Swift Projection Parity Baseline Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/architecture.md#swift-port-architecture
**Created**: 2026-06-19
**Last Updated**: 2026-06-19

## Design Document Reference

This plan ports the next Swift read-projection baseline. Swift already requests
media and referenced-post expansions for read routes, but the initial projector
dropped those fields from public responses. This slice maps returned expansions
into the same public response shape used by the TypeScript contract.

Out of scope:
- local media download to `mediaRootDir`
- nested `Post.replies(...)` execution
- promoted-post filtering parity

## Modules

### 1. Public Schema Projection Fields

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftProjectedPostFields = {
  metrics: "PostMetrics";
  media?: "MediaAsset[]";
  referencedPosts?: "ReferencedPost[]";
};
```

**Status**: Completed

**Checklist**:
- [x] Add media asset fields to Swift schema output
- [x] Add referenced post fields and shortcuts to Swift schema output
- [x] Keep existing read/write command split unchanged

### 2. Projection Context

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftProjectionContext = {
  usersById: Record<string, Account>;
  mediaByKey: Record<string, MediaAsset>;
  tweetsById: Record<string, Tweet>;
};
```

**Status**: Completed

**Checklist**:
- [x] Index included users, media, top-level tweets, and included tweets
- [x] Reuse one projector for post lookup and post pages
- [x] Preserve nullable metric behavior

### 3. Media and References

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftReferenceProjection = {
  relation: "replied_to" | "quoted" | "retweeted";
  shortcuts: "replyTo" | "quote" | "repost";
};
```

**Status**: Completed

**Checklist**:
- [x] Project media kind, content type, source URL, and preview image URL
- [x] Project referenced posts with relation
- [x] Project `replyTo`, `quote`, and `repost` shortcuts
- [x] Add Swift smoke coverage for media and quote projection

## Module Status

| Module | File Path | Status | Tests |
|--------|-----------|--------|-------|
| Public schema projection fields | `Sources/XGatewayCore/XGatewayCore.swift` | Completed | Covered |
| Projection context | `Sources/XGatewayCore/XGatewayCore.swift` | Completed | Covered |
| Media/reference projection | `Sources/XGatewayCore/XGatewayCore.swift`, `Sources/XGatewaySwiftSmokeTests/main.swift` | Completed | Covered |

## Dependencies

| Feature | Depends On | Status |
|---------|------------|--------|
| TASK-001: Schema fields | Swift split commands | Completed |
| TASK-002: Projection context | TASK-001 | Completed |
| TASK-003: Media/reference projection | TASK-002 | Completed |

## Tasks

### TASK-001: Schema Fields

**Status**: Completed
**Parallelizable**: Yes
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`
**Dependencies**: x-gateway-swift-port-split-commands:TASK-002

**Completion Criteria**:
- [x] Swift schema includes media, metrics, and referenced-post fields
- [x] Schema remains available from both read and write commands

### TASK-002: Projection Context

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`
**Dependencies**: TASK-001

**Completion Criteria**:
- [x] Projector can resolve included authors, media, and referenced tweets
- [x] Post lookup and timeline pages share projection behavior

### TASK-003: Media and Reference Projection

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`, `Sources/XGatewaySwiftSmokeTests/main.swift`
**Dependencies**: TASK-002

**Completion Criteria**:
- [x] Swift projects media asset URLs and inferred content types
- [x] Swift projects referenced posts and quote/reply/repost shortcuts
- [x] Smoke tests cover the richer projection shape

## Completion Criteria

- [x] Swift no longer drops media expansion data from read responses
- [x] Swift no longer drops referenced-post expansion data from read responses
- [x] Swift smoke tests cover the projection baseline
- [x] User-facing docs describe the new projection boundary

## Progress Log

### Session: 2026-06-19 16:05
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None for this projection slice.
**Notes**: Added Swift schema fields and context-based projection for media assets and referenced posts, including quote/reply/repost shortcuts when upstream expansions are present.
