# X Gateway Media Upload Baseline Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/architecture.md#capability-matrix-implementation-target
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- design-docs/specs/architecture.md
- design-docs/specs/command.md
- design-docs/specs/design-api-inventory.md
- design-docs/specs/notes.md

### Summary
Implement the next practical stable capability slice after the hybrid read/post baseline: reviewed media upload adapters that support image-first posting workflows without forcing callers onto raw X web GraphQL as the primary interface.

### Scope
**Included**:
- stable media upload capability contract for CLI and SDK
- reviewed OAuth1-compatible upload baseline
- attachment of uploaded media to stable posting helpers where the adapter contract is implemented
- diagnostics, capability inventory, and tests for the delivered media path

**Excluded**:
- article/long-form publishing
- video/chunked upload if it cannot be completed safely in the same slice
- undocumented/private upload flows without reviewed adapter contracts
- broad timeline/social/DM expansion

---

## Tasks

### TASK-001: Media Capability Contract
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.ts` media capability interfaces and adapter boundary
- capability registry rows for the first reviewed media operations
- CLI contract updates for the media commands that become stable in this slice

**Completion Criteria**:
- [x] Media capabilities are represented as stable intent-level operations
- [x] Capability metadata documents auth mode and transport strategy accurately
- [x] Unsupported media variants remain explicitly blocked with remediation

### TASK-002: OAuth1 Upload Adapter
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- OAuth1-backed media upload adapter using the reviewed public upload path
- normalized response mapping for uploaded media identifiers
- actionable error mapping for upload-specific failures

**Completion Criteria**:
- [x] At least one reviewed upload path is implemented end to end
- [x] Upload failures normalize to existing x-gateway error semantics
- [x] Tests cover auth, validation, and representative upstream failures

### TASK-003: Post-With-Media Integration
**Status**: Completed
**Parallelizable**: No (depends on TASK-002)
**Deliverables**:
- stable post helper integration for uploaded media identifiers
- request contracts for image-backed post creation
- CLI flag wiring for the delivered attachment flow

**Completion Criteria**:
- [x] Stable post creation can attach uploaded media through the reviewed adapter path
- [x] CLI and SDK contracts stay transport-agnostic
- [x] Bearer-only environments remain rejected unless a reviewed posting path exists

### TASK-004: Verification and Docs
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- unit/contract tests for upload and attachment flows
- design/inventory/doc updates for the delivered slice
- plan progress updates and validation evidence

**Completion Criteria**:
- [x] Typecheck passes
- [x] Tests pass
- [x] Build passes
- [x] Docs and capability inventory match delivered behavior

---

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Media capability contract | `src/lib.ts` | COMPLETED | Covered |
| Public GraphQL parser/contract | `src/public-graphql-parser.ts`, `src/public-api-contract.ts` | COMPLETED | Covered |
| OAuth1 upload adapter | `src/capability-adapters.ts` | COMPLETED | Covered |
| Capability inventory/docs | `design-docs/specs/*.md` | COMPLETED | N/A |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-002 |
| TASK-004 | TASK-001, TASK-002, TASK-003 |

## Completion Criteria

- [x] Stable media upload baseline is restored without exposing raw transport details as the default product interface
- [x] Auth and transport constraints for media operations are enforced in code and documented in the capability inventory
- [x] Upload and post-with-media flows have regression coverage
- [x] Tests and type checks pass for delivered scope

## Progress Log

### Session: 2026-03-08
**Tasks Completed**: None
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Created the next active plan after the hybrid read/post baseline was completed.
- This slice is sequenced ahead of broader timeline/social recovery because media upload is a direct prerequisite for the product’s promised post-with-image workflows.

### Session: 2026-03-08 14:18 JST
**Tasks Completed**: TASK-001, TASK-002, TASK-003, TASK-004
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Confirmed the architecture already matched the intended canonical public GraphQL direction, so the iteration stayed within the existing design rather than introducing a replacement architecture.
- Finished project-owned GraphQL list/object literal parsing and attachment input validation for `createPost`, `replyToPost`, and `quotePost`.
- Integrated OAuth1 media upload plus optional alt-text application into the stable posting adapter without exposing upload sequencing to callers.
- Corrected capability truthfulness by removing bearer-only `likes` claims from the reviewed stable surface until a live route is verified.
- Added regression coverage for attachment-backed SDK and `api request` flows, parser behavior, sparse optional projection, and `likes` auth-routing behavior.
- Verified with `bun run typecheck`, `bun test`, and `bun run build`.
