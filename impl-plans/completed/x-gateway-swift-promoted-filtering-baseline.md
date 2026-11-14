# x-gateway Swift Promoted Filtering Baseline Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/command.md#swift-split-commands
**Created**: 2026-06-19
**Last Updated**: 2026-06-19

## Design Document Reference

This plan ports the Swift promoted-post filtering baseline. The TypeScript
contract filters promoted posts by default and allows callers to opt in with
`includePromoted: true`; Swift previously projected every post with
`promotionStatus: "UNKNOWN"`.

Out of scope:
- local media download to `mediaRootDir`
- nested `Post.replies(...)` execution
- live credential-specific verification of owner-only metric availability

## Modules

### 1. Public Read Arguments

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftReadPromotedOption = {
  includePromoted?: boolean;
};
```

**Status**: Completed

**Checklist**:
- [x] Add `includePromoted` to Swift read schema fields
- [x] Parse boolean literals from project-owned GraphQL reads
- [x] Default `includePromoted` to false

### 2. Metric Field Requests

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftMetricFieldPolicy = "default" | "public-only";
```

**Status**: Completed

**Checklist**:
- [x] Request organic/promoted metrics for normal Swift read routes
- [x] Keep followed-account fanout public-only
- [x] Preserve nullable impression-count behavior

### 3. Projection Filtering

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftPromotionStatus = "PROMOTED" | "NOT_PROMOTED" | "UNKNOWN";
```

**Status**: Completed

**Checklist**:
- [x] Detect promoted posts from promoted metric payloads
- [x] Detect not-promoted posts from organic metric payloads
- [x] Filter promoted posts by default in page projections
- [x] Reject top-level promoted post lookup unless `includePromoted` is true

## Module Status

| Module | File Path | Status | Tests |
|--------|-----------|--------|-------|
| Public read arguments | `Sources/XGatewayCore/XGatewayCore.swift` | Completed | Covered |
| Metric field requests | `Sources/XGatewayCore/XGatewayCore.swift` | Completed | Covered |
| Projection filtering | `Sources/XGatewayCore/XGatewayCore.swift`, `Sources/XGatewaySwiftSmokeTests/main.swift` | Completed | Covered |

## Dependencies

| Feature | Depends On | Status |
|---------|------------|--------|
| TASK-001: Public read arguments | Swift projection parity baseline | Completed |
| TASK-002: Metric field requests | TASK-001 | Completed |
| TASK-003: Projection filtering | TASK-002 | Completed |

## Tasks

### TASK-001: Public Read Arguments

**Status**: Completed
**Parallelizable**: Yes
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`
**Dependencies**: x-gateway-swift-projection-parity-baseline:TASK-001

**Completion Criteria**:
- [x] Swift schema advertises `includePromoted`
- [x] Swift parser accepts `includePromoted: true` and `false`

### TASK-002: Metric Field Requests

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`
**Dependencies**: TASK-001

**Completion Criteria**:
- [x] Swift normal read routes can receive organic/promoted metrics
- [x] Swift followed-account fanout still avoids owner-only metric fields

### TASK-003: Projection Filtering

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`, `Sources/XGatewaySwiftSmokeTests/main.swift`
**Dependencies**: TASK-002

**Completion Criteria**:
- [x] Promoted page posts are filtered by default
- [x] `includePromoted: true` keeps promoted posts
- [x] Top-level promoted post lookup returns permission guidance by default

## Completion Criteria

- [x] Swift read schema and parser support `includePromoted`
- [x] Swift projection maps `PROMOTED`, `NOT_PROMOTED`, and `UNKNOWN`
- [x] Swift filters promoted posts by default
- [x] Swift smoke tests cover promoted filtering and opt-in behavior

## Progress Log

### Session: 2026-06-19 16:35
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None for this promoted filtering slice.
**Notes**: Added Swift `includePromoted` parsing, owner-metric request policy, promotion status detection, default filtering, top-level promoted lookup rejection, and smoke coverage.
