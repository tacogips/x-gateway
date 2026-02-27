# X Gateway Full API Coverage Implementation Plan

**Status**: Ready
**Design Reference**: design-docs/specs/architecture.md#capability-matrix-implementation-target
**Created**: 2026-02-27
**Last Updated**: 2026-02-27

---

## Design Document Reference

**Source**:
- design-docs/specs/command.md
- design-docs/specs/architecture.md
- design-docs/specs/notes.md

### Summary
Implement `x-gateway` as an AI-optimized CLI plus reusable TypeScript library with broad X API support, rich error diagnostics, and dual configuration input (env + parameters).

### Scope
**Included**:
- CLI command groups and SDK entry points
- shared service/gateway architecture
- auth/config handling with parameter precedence
- detailed typed error mapping with remediation guidance
- post pattern support (normal/reply/quote/repost/media/article/referenced-content retrieval)
- phased endpoint implementation with tests

**Excluded**:
- undocumented/private X API behavior
- breaking changes to established command names after stabilization without migration notes

---

## Tasks

### TASK-001: PoC Import and Repository Baseline
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- PoC sources copied from `/g/gits/tacogips/x-sdk-test`
- local private env bootstrap file copied (`.envrc.private`)
- dependency manifest aligned with PoC baseline

**Completion Criteria**:
- [x] PoC source files imported
- [x] `.envrc.private` copied
- [x] Repository remains buildable baseline after import

### TASK-002: Public SDK Surface and Config Inputs
**Status**: Not Started
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/lib/` public client factory and typed operation interfaces
- request-level config objects supporting both env-derived and parameter-provided credentials
- precedence and validation rules documented and tested

**Completion Criteria**:
- [ ] Parameter-only client initialization supported
- [ ] Env-only initialization supported
- [ ] Mixed-mode precedence behavior defined and tested
- [ ] Credential validation failures are actionable

### TASK-003: Error Taxonomy and Message Composer
**Status**: Not Started
**Parallelizable**: Yes
**Deliverables**:
- error code taxonomy module
- mapper from X API errors/network/runtime failures to internal error classes
- user and AI friendly message composition with likely causes and recovery actions

**Completion Criteria**:
- [ ] Stable internal error codes defined
- [ ] Permission vs token-expired vs token-revoked distinctions validated
- [ ] Rate-limit diagnostic detail includes reset/retry hints
- [ ] JSON error envelope schema documented

### TASK-004: CLI Command Surface
**Status**: Not Started
**Parallelizable**: No (depends on TASK-002 and TASK-003)
**Deliverables**:
- `src/main.ts` command router and subcommand handlers
- structured output modes (`text`, `json`)
- exit-code mapping aligned with design-docs/specs/command.md

**Completion Criteria**:
- [ ] Command groups implemented per command design
- [ ] Global flags (`--json`, `--auth-mode`, `--trace-id`, etc.) operational
- [ ] Exit codes mapped to error categories
- [ ] CLI behavior parity with SDK operations for shared features

### TASK-005: Posting Pattern Implementation
**Status**: Not Started
**Parallelizable**: No (depends on TASK-002, TASK-003)
**Deliverables**:
- operations for create/reply/quote/repost/delete
- media upload flows for image/video attachments
- referenced/original content retrieval utilities for quote/reply/repost chains
- article/long-form publish path when supported by configured API scope

**Completion Criteria**:
- [ ] Text/reply/quote/repost flows implemented
- [ ] Image/video attachment flows implemented
- [ ] Quote source and thread expansion retrieval implemented
- [ ] Failure modes produce detailed actionable diagnostics

### TASK-006: Broader Endpoint Coverage
**Status**: Not Started
**Parallelizable**: Yes
**Deliverables**:
- users, timelines, likes, bookmarks, follows, mentions, account identity APIs
- DM support path where credentials and tier permit
- capability registry documenting support, scope, and limitations

**Completion Criteria**:
- [ ] Endpoint modules implemented with shared gateway conventions
- [ ] Capability registry completed
- [ ] Unsupported endpoints return explicit guidance (not generic failure)

### TASK-007: Verification and Hardening
**Status**: Not Started
**Parallelizable**: No (depends on TASK-004, TASK-005, TASK-006)
**Deliverables**:
- unit + integration test suites
- contract-style fixtures for representative X API responses/errors
- docs updates for usage, limitations, and troubleshooting

**Completion Criteria**:
- [ ] Typecheck passes
- [ ] Test suite passes
- [ ] Error-message quality validated for key failure categories
- [ ] Design + plan docs updated to reflect delivered scope

---

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| PoC baseline | `src/` | COMPLETED | Pending |
| SDK surface | `src/lib/` | NOT_STARTED | Pending |
| CLI surface | `src/main.ts` + `src/cli/` | NOT_STARTED | Pending |
| Error system | `src/errors/` | NOT_STARTED | Pending |
| Gateway adapters | `src/gateway/` | NOT_STARTED | Pending |
| Capability registry/docs | `design-docs/specs/` | IN_PROGRESS | Pending |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-004 | TASK-002, TASK-003 |
| TASK-005 | TASK-002, TASK-003 |
| TASK-007 | TASK-004, TASK-005, TASK-006 |

## Completion Criteria

- [ ] CLI and SDK surfaces both production-ready
- [ ] Full targeted capability matrix implemented or explicitly documented as unavailable
- [ ] Post pattern support complete (normal/reply/quote/repost/media/article/reference retrieval)
- [ ] Error diagnostics are detailed and actionable for AI callers
- [ ] Tests and type checks pass in CI baseline

## Progress Log

### Session: 2026-02-27
**Tasks Completed**: TASK-001
**Tasks In Progress**: Documentation baseline for architecture/commands/notes
**Blockers**: None
**Notes**: Bootstrapped scope and imported PoC baseline to begin phased implementation.

## Related Plans

- **Previous**: None
- **Next**: Split plans may be created by endpoint family if this plan approaches size/task limits
- **Depends On**: design-docs/specs/command.md, design-docs/specs/architecture.md, design-docs/specs/notes.md
