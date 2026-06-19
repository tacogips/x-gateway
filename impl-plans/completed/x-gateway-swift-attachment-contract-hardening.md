# x-gateway Swift Attachment Contract Hardening Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/command.md#swift-split-commands
**Created**: 2026-06-19
**Last Updated**: 2026-06-19

## Design Document Reference

This plan hardens the Swift write command during the Swift migration. The
TypeScript public GraphQL contract supports `attachments` on `createPost`,
`replyToPost`, and `quotePost`; at the time this plan was executed, Swift
media upload had not been ported yet. This slice prevented Swift from accepting
attachment intent and posting text without media.

Historical note: this plan captured the temporary safety boundary before Swift
media upload was ported. The follow-up media upload implementation is tracked
in `completed/x-gateway-swift-media-upload-baseline.md`.

Out of scope:
- Swift OAuth1 media upload
- Swift alt-text metadata upload
- video or article publishing

## Modules

### 1. Swift Attachment Input Parsing

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftAttachmentInput = {
  kind: "image";
  filePath: string;
  altText?: string;
};

type SwiftAttachmentParseResult =
  | { status: "omitted" }
  | { status: "valid"; attachments: SwiftAttachmentInput[] }
  | { status: "validation-error"; message: string };
```

**Status**: Completed

**Checklist**:
- [x] Detect `attachments:` in post mutation arguments
- [x] Parse project-owned list and object literals
- [x] Validate image-only attachment objects
- [x] Reject extra fields and invalid values

### 2. Swift Unsupported Boundary

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftAttachmentUploadBoundary = {
  validAttachmentInput: "UNSUPPORTED";
  invalidAttachmentInput: "VALIDATION_ERROR";
};
```

**Status**: Completed

**Checklist**:
- [x] Return `UNSUPPORTED` for valid attachment-backed Swift post mutations
- [x] Keep text-only Swift bearer posting behavior unchanged
- [x] Avoid live posting when attachment intent is present

### 3. Swift Smoke Coverage

#### Sources/XGatewaySwiftSmokeTests/main.swift

```typescript
type SwiftAttachmentSmokeCase = {
  mutation: "createPost" | "replyToPost" | "quotePost";
  expectedCode: "UNSUPPORTED" | "VALIDATION_ERROR";
};
```

**Status**: Completed

**Checklist**:
- [x] Cover valid `createPost` attachment rejection
- [x] Cover valid `replyToPost` attachment rejection
- [x] Cover valid `quotePost` attachment rejection
- [x] Cover malformed attachment validation failures

## Module Status

| Module | File Path | Status | Tests |
|--------|-----------|--------|-------|
| Swift attachment input parsing | `Sources/XGatewayCore/XGatewayCore.swift` | Completed | Covered |
| Swift unsupported boundary | `Sources/XGatewayCore/XGatewayCore.swift` | Completed | Covered |
| Swift smoke coverage | `Sources/XGatewaySwiftSmokeTests/main.swift` | Completed | Covered |

## Dependencies

| Feature | Depends On | Status |
|---------|------------|--------|
| TASK-001: Attachment parser | Swift split commands | Completed |
| TASK-002: Unsupported boundary | TASK-001 | Completed |
| TASK-003: Smoke coverage and docs | TASK-001, TASK-002 | Completed |

## Tasks

### TASK-001: Attachment Parser

**Status**: Completed
**Parallelizable**: Yes
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`
**Dependencies**: x-gateway-swift-port-split-commands:TASK-002

**Completion Criteria**:
- [x] Swift recognizes attachment list literals on post mutations
- [x] Swift validates allowed fields, kind, filePath, and altText bounds

### TASK-002: Unsupported Attachment Upload Boundary

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`
**Dependencies**: TASK-001

**Completion Criteria**:
- [x] Valid attachment-backed Swift mutations fail with `UNSUPPORTED`
- [x] Swift cannot silently omit requested attachments during live posting

### TASK-003: Tests and Documentation

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewaySwiftSmokeTests/main.swift`, `README.md`, `design-docs/specs/architecture.md`, `design-docs/specs/command.md`
**Dependencies**: TASK-001, TASK-002

**Completion Criteria**:
- [x] Swift smoke tests cover attachment rejection and validation failures
- [x] User-facing docs stated the temporary Swift attachment safety boundary

## Completion Criteria

- [x] Attachment-backed Swift mutations are not silently downgraded to text-only posts
- [x] Malformed attachment input fails with validation guidance
- [x] Valid attachment input fails with explicit unsupported Swift media-upload guidance
- [x] Swift smoke tests pass

## Progress Log

### Session: 2026-06-19 14:15
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None for this hardening slice.
**Notes**: Added Swift attachment literal parsing and validation for `createPost`, `replyToPost`, and `quotePost`; valid attachments now fail as unsupported until Swift media upload is ported, preventing text-only live posts that ignore requested media.
