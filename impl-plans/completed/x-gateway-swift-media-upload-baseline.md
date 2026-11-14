# x-gateway Swift Media Upload Baseline Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/command.md#swift-split-commands
**Created**: 2026-06-19
**Last Updated**: 2026-06-19

## Design Document Reference

This plan ports the attachment-backed Swift posting baseline. The TypeScript
public GraphQL contract supports image attachments on `createPost`,
`replyToPost`, and `quotePost`; Swift now needs to execute that contract rather
than only validating and rejecting valid attachment input.

Out of scope:
- video upload
- article or long-form publishing
- media download and nested hydration projection parity

## Modules

### 1. Attachment-Aware Mutation Model

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftAttachmentMutation =
  | { field: "createPost"; attachments?: SwiftAttachmentInput[] }
  | { field: "replyToPost"; attachments?: SwiftAttachmentInput[] }
  | { field: "quotePost"; attachments?: SwiftAttachmentInput[] };
```

**Status**: Completed

**Checklist**:
- [x] Carry parsed attachments into supported mutation operations
- [x] Require OAuth1 for attachment-backed writes
- [x] Preserve bearer fallback for text-only writes

### 2. OAuth1 Media Upload

#### Sources/XGatewayCore/XGatewayCore.swift

```typescript
type SwiftMediaUploadRoute = {
  init: "POST /1.1/media/upload.json command=INIT";
  append: "POST /1.1/media/upload.json command=APPEND";
  finalize: "POST /1.1/media/upload.json command=FINALIZE";
  metadata: "POST /1.1/media/metadata/create.json";
};
```

**Status**: Completed

**Checklist**:
- [x] Read and validate local image file paths before upload
- [x] Upload image chunks through OAuth1 media upload
- [x] Apply alt text metadata when provided
- [x] Include uploaded `media_ids` in the v2 tweet body

### 3. Smoke Coverage and Documentation

#### Sources/XGatewaySwiftSmokeTests/main.swift

```typescript
type SwiftMediaUploadSmoke = {
  noOAuth1: "AUTH_MISSING";
  missingFileWithOAuth1: "VALIDATION_ERROR";
};
```

**Status**: Completed

**Checklist**:
- [x] Cover OAuth1 requirement for attachment-backed mutations
- [x] Cover local file validation before upload
- [x] Update README and design docs to describe Swift media upload support

## Module Status

| Module | File Path | Status | Tests |
|--------|-----------|--------|-------|
| Attachment-aware mutation model | `Sources/XGatewayCore/XGatewayCore.swift` | Completed | Covered |
| OAuth1 media upload | `Sources/XGatewayCore/XGatewayCore.swift` | Completed | Covered |
| Smoke/docs coverage | `Sources/XGatewaySwiftSmokeTests/main.swift`, docs | Completed | Covered |

## Dependencies

| Feature | Depends On | Status |
|---------|------------|--------|
| TASK-001: Attachment-aware mutation model | Swift attachment contract hardening | Completed |
| TASK-002: OAuth1 media upload | Swift OAuth1 signing baseline | Completed |
| TASK-003: Tests and documentation | TASK-001, TASK-002 | Completed |

## Tasks

### TASK-001: Attachment-Aware Mutation Model

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`
**Dependencies**: x-gateway-swift-attachment-contract-hardening:TASK-001

**Completion Criteria**:
- [x] Attachments are retained through parse and execution
- [x] Attachment-backed writes cannot silently downgrade to text-only posts

### TASK-002: OAuth1 Media Upload

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewayCore/XGatewayCore.swift`
**Dependencies**: x-gateway-swift-oauth1-signing-baseline:TASK-002

**Completion Criteria**:
- [x] Swift uploads image files with OAuth1 before v2 tweet creation
- [x] Swift applies alt text metadata when provided
- [x] Swift v2 tweet bodies include uploaded media ids

### TASK-003: Smoke Coverage and Documentation

**Status**: Completed
**Parallelizable**: No
**Deliverables**: `Sources/XGatewaySwiftSmokeTests/main.swift`, `README.md`, `design-docs/specs/architecture.md`, `design-docs/specs/command.md`
**Dependencies**: TASK-001, TASK-002

**Completion Criteria**:
- [x] Smoke tests cover OAuth1-required attachment routing
- [x] Smoke tests cover local file validation with OAuth1 configured
- [x] Public docs state Swift supports image attachment upload for post mutations

## Completion Criteria

- [x] Attachment-backed Swift mutations require OAuth1 and no longer fail as unsupported
- [x] Image attachments upload before tweet creation
- [x] Alt text is applied through media metadata when provided
- [x] Swift smoke tests pass for the media-upload boundary

## Progress Log

### Session: 2026-06-19 15:30
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None for this media upload slice.
**Notes**: Replaced the temporary unsupported attachment boundary with OAuth1 media upload, alt-text metadata creation, attachment-aware tweet bodies, auth/file validation smoke coverage, and public documentation updates.
