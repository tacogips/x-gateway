# x-gateway Swift Nested Replies Baseline Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/command.md#swift-split-commands
**Created**: 2026-06-19
**Last Updated**: 2026-06-19

## Design Document Reference

This plan ports the Swift baseline for reviewed nested `Post.replies(...)`
execution. Swift already handled top-level reads and projections; this slice
adds bounded nested reply hydration through the same recent-search transport
used by the TypeScript stable capability.

Out of scope:
- general nested GraphQL resolver execution for arbitrary fields
- live credential-specific verification of every pagination edge case

## Modules

### 1. Public Schema and Parser

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftReplyExpansion = {
  maxResults?: number;
  paginationToken?: string;
  mediaRootDir?: string;
  downloadMedia?: boolean;
  forceDownload?: boolean;
  includePromoted?: boolean;
};
```

**Status**: Completed

**Checklist**:
- [x] Add `Post.replies(...)` to the Swift schema
- [x] Parse nested reply arguments from read documents
- [x] Reject unsupported nested reply arguments before live execution

### 2. Nested Reply Hydration

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftReplyHydration = "single-post" | "post-page";
```

**Status**: Completed

**Checklist**:
- [x] Hydrate replies for top-level `post` results
- [x] Hydrate replies for timeline/search page posts
- [x] Enforce the bounded nested reply expansion limit
- [x] Validate reply lookup post ids before building search queries

### 3. Smoke Coverage and Documentation

#### Sources/XGatewaySwiftSmokeTests/main.swift

**Status**: Completed

**Checklist**:
- [x] Verify schema exposure for nested `Post.replies`
- [x] Verify unsupported nested reply arguments fail validation
- [x] Update README and design specs

## Module Status

| Module | File Path | Status | Tests |
|--------|-----------|--------|-------|
| Public schema and parser | `Sources/XGatewayCore/XGatewayCore.swift` | Completed | Covered |
| Nested reply hydration | `Sources/XGatewayCore/XGatewayCore.swift` | Completed | Covered |
| Smoke coverage and documentation | `Sources/XGatewaySwiftSmokeTests/main.swift`, `README.md`, `design-docs/specs/architecture.md`, `design-docs/specs/command.md` | Completed | Covered |

## Dependencies

| Feature | Depends On | Status |
|---------|------------|--------|
| TASK-001: Public schema and parser | Swift projection parity baseline | Completed |
| TASK-002: Nested reply hydration | TASK-001 | Completed |
| TASK-003: Smoke coverage and documentation | TASK-002 | Completed |

## Tasks

### TASK-001: Public Schema and Parser

**Status**: Completed
**Parallelizable**: Yes
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`
**Dependencies**: x-gateway-swift-projection-parity-baseline:TASK-001

**Completion Criteria**:
- [x] Swift schema advertises nested `Post.replies`
- [x] Swift parser accepts supported nested reply arguments
- [x] Swift parser rejects unsupported nested reply arguments

### TASK-002: Nested Reply Hydration

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`
**Dependencies**: TASK-001

**Completion Criteria**:
- [x] Swift uses `in_reply_to_tweet_id:<post-id>` recent search for replies
- [x] Swift hydrates replies on single posts and page posts
- [x] Swift recursively hydrates explicitly nested reply selections
- [x] Swift enforces a bounded per-request expansion limit

### TASK-003: Smoke Coverage and Documentation

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewaySwiftSmokeTests/main.swift`, `README.md`, `design-docs/specs/architecture.md`, `design-docs/specs/command.md`
**Dependencies**: TASK-002

**Completion Criteria**:
- [x] Swift smoke tests cover schema and nested argument validation
- [x] README documents Swift nested replies as supported
- [x] Design docs describe bounded Swift reply hydration

## Completion Criteria

- [x] Swift schema and parser support nested `Post.replies`
- [x] Swift live executor hydrates nested replies for post and page reads
- [x] Swift enforces reply expansion bounds and safe search-token validation
- [x] Public docs and plan tracking reflect the completed slice

## Progress Log

### Session: 2026-06-19 17:35
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None for this nested replies slice.
**Notes**: Added Swift `Post.replies` schema support, nested reply argument parsing, bounded recursive reply hydration through recent search, invalid argument smoke coverage, and documentation updates.
