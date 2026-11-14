# X Gateway Full API Coverage Implementation Plan

**Status**: Superseded
**Design Reference**: Historical baseline; superseded by `impl-plans/completed/x-gateway-hybrid-capability-adapters.md`
**Created**: 2026-02-27
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- design-docs/specs/command.md
- design-docs/specs/architecture.md
- design-docs/specs/notes.md

### Summary
This plan captures the earlier GraphQL-first baseline. It is retained for history only and is superseded for new implementation work by `impl-plans/completed/x-gateway-hybrid-capability-adapters.md`, which restores stable capability adapters as the primary contract.

### Scope
**Included**:
- GraphQL-first CLI command groups and SDK entry points
- shared service/gateway architecture
- auth/config handling with parameter precedence
- detailed typed error mapping with remediation guidance
- capability registry plus explicit unsupported guidance
- phased GraphQL mapping implementation with tests

**Excluded**:
- undocumented/private X API behavior
- high-level helper reintroduction without committed GraphQL mapping artifacts
- hybrid capability-adapter restoration work tracked in the superseding plan

---

## Tasks

### TASK-001: PoC Import and Repository Baseline
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- PoC sources copied from `/g/gits/tacogips/x-sdk-test`
- local private env bootstrap file copied (`.env.example`)
- dependency manifest aligned with PoC baseline

**Completion Criteria**:
- [x] PoC source files imported
- [x] `.env.example` copied
- [x] Repository remains buildable baseline after import

### TASK-002: Public SDK Surface and Config Inputs
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/lib.ts` public client factory and typed operation interfaces
- request-level config objects supporting both env-derived and parameter-provided credentials
- precedence and validation rules documented and tested

**Completion Criteria**:
- [x] Parameter-only client initialization supported
- [x] Env-only initialization supported
- [x] Mixed-mode precedence behavior defined and tested
- [x] Credential validation failures are actionable
- [x] Stable SDK surface reduced to GraphQL-first request contract plus local diagnostics

### TASK-003: Error Taxonomy and Message Composer
**Status**: In Progress
**Parallelizable**: Yes
**Deliverables**:
- error code taxonomy module
- mapper from X API errors/network/runtime failures to internal error classes
- user and AI friendly message composition with likely causes and recovery actions

**Completion Criteria**:
- [x] Stable internal error codes defined
- [x] Permission vs token-expired vs token-revoked distinctions validated
- [x] Rate-limit diagnostic detail includes reset/retry hints
- [x] Retry exhaustion diagnostics include backoff strategy, attempts, and elapsed wait details
- [x] JSON error envelope schema documented

### TASK-004: CLI Command Surface
**Status**: Completed
**Parallelizable**: No (depends on TASK-002 and TASK-003)
**Deliverables**:
- `src/main.ts` command router and subcommand handlers
- structured output modes (`text`, `json`)
- exit-code mapping aligned with design-docs/specs/command.md

**Completion Criteria**:
- [x] Command groups implemented per command design
- [x] Global flags (`--json`, `--auth-mode`, `--trace-id`, retry controls, etc.) operational
- [x] Exit codes mapped to error categories
- [x] CLI behavior parity with SDK operations for shared features
- [x] Unmapped legacy command groups rejected at the CLI boundary

### TASK-005: Posting Pattern Implementation
**Status**: In Progress
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
- [x] Failure modes produce detailed actionable diagnostics

### TASK-006: Broader Endpoint Coverage
**Status**: In Progress
**Parallelizable**: Yes
**Deliverables**:
- users, timelines, likes, bookmarks, follows, mentions, account identity APIs
- DM support path where credentials and tier permit
- capability registry documenting support, scope, and limitations

**Completion Criteria**:
- [ ] Endpoint modules implemented with shared gateway conventions
- [x] Capability registry completed
- [ ] Unsupported endpoints return explicit guidance (not generic failure)

### TASK-007: Verification and Hardening
**Status**: In Progress
**Parallelizable**: No (depends on TASK-004, TASK-005, TASK-006)
**Deliverables**:
- unit + integration test suites
- contract-style fixtures for representative X API responses/errors
- docs updates for usage, limitations, and troubleshooting

**Completion Criteria**:
 - [x] Typecheck passes
 - [x] Test suite passes
 - [ ] Error-message quality validated for key failure categories
 - [x] Network failure retry/backoff behavior covered by tests
 - [x] Design + plan docs updated to reflect delivered scope

---

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| PoC baseline | `src/` | COMPLETED | Pending |
| SDK surface | `src/lib.ts` | COMPLETED | Partial |
| CLI surface | `src/main.ts` + `src/cli.ts` | COMPLETED | Partial |
| Error system | `src/lib.ts` | IN_PROGRESS | Pending |
| Gateway adapters | `src/lib.ts` | IN_PROGRESS | Pending |
| Capability registry/docs | `design-docs/specs/` | IN_PROGRESS | Partial |

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

### Session: 2026-02-27 (Implementation Pass)
**Tasks Completed**: Partial progress on TASK-002, TASK-003, TASK-004, TASK-005, TASK-006
**Tasks In Progress**: CLI/SDK coverage expansion and capability completion
**Blockers**: No blocker; verification is intentionally deferred per instruction
**Notes**:
- Implemented shared SDK with `X_GW_` env + parameter precedence.
- Added detailed error normalization with actionable diagnostics and exit-code mapping.
- Added retry + backoff transport policy in code.
- Expanded CLI and SDK coverage: auth, posts, media, timelines, mentions, users, likes, bookmarks, follows, search, DMs, tweet engagement views.

### Session: 2026-02-27 (Implementation Pass 2)
**Tasks Completed**: Additional progress on TASK-004, TASK-005, TASK-006
**Tasks In Progress**: Remaining unsupported-guidance edge cases and verification tasks
**Blockers**: Verification remains deferred per instruction
**Notes**:
- Added runtime `authMode` support (`env`/`params`/`mixed`) and strict capability checks.
- Implemented capability registry accessors and CLI commands (`capabilities list|get`).
- Added media-file upload-and-post workflow with optional alt text mapping.
- Extended pagination and batch operations across search/timeline/users endpoints.

### Session: 2026-03-08 (GraphQL-Only Transport Pivot)
**Tasks Completed**: Additional progress on TASK-002, TASK-003, TASK-004, TASK-005, TASK-006
**Tasks In Progress**: GraphQL operation mapping for high-level convenience methods
**Blockers**: Concrete X GraphQL operation ids/documents and variable schemas are not yet defined in-repo
**Notes**:
- Removed live REST transport usage from `src/lib.ts` and replaced raw transport with GraphQL-only `fetch` requests.
- Converted legacy REST-shaped convenience methods into explicit `UNSUPPORTED` errors so no hidden REST access remains.
- Disabled `src/x-account-fetch.ts` because it previously depended on `twitter-api-v2` REST endpoints.
- Added GraphQL transport tests and revalidated typecheck, unit tests, and build.

### Session: 2026-03-08 (GraphQL-First Contract Alignment)
**Tasks Completed**: Additional progress on TASK-002, TASK-004, TASK-006
**Tasks In Progress**: Concrete GraphQL mapping definitions for high-level helpers
**Blockers**: High-level endpoint support remains blocked until persisted query ids or inline query contracts are committed
**Notes**:
- Updated design docs to make raw GraphQL request input the primary supported contract across CLI and SDK.
- Added `graphql request` as a first-class CLI command and enforced query-only mode in `x-gateway-reader`.
- Fixed eager auth resolution so capability inspection and local auth diagnostics work without configured credentials.
- Tightened compatibility messaging so unsupported helpers explicitly direct callers to raw GraphQL input or missing mapping work.

### Session: 2026-03-08 (Review and Hardening Pass)
**Tasks Completed**: Additional progress on TASK-003, TASK-004, TASK-007
**Tasks In Progress**: Verification hardening and GraphQL mapping backlog
**Blockers**: High-level convenience methods remain blocked on concrete GraphQL mapping artifacts
**Notes**:
- Fixed CLI flag validation so missing/invalid flags now report `VALIDATION_ERROR` instead of internal failure.
- Enforced the documented GraphQL request contract requiring exactly one of `documentId` or inline `query`.
- Added `Retry-After` parsing and retry-exhaustion context so transport behavior better matches the architecture spec.
- Switched the package test script to `bun test` because the current `vitest run` path was not terminating reliably in this repository state.
- Re-ran `bun run test`, `bun run typecheck`, and `bun run build` successfully after the fixes.

### Session: 2026-03-08 (GraphQL-Only Surface Reduction)
**Tasks Completed**: Additional progress on TASK-002, TASK-004, TASK-007
**Tasks In Progress**: Documentation and capability hardening for future explicit mappings
**Blockers**: Reviewed GraphQL mappings are still absent for high-level endpoint families
**Notes**:
- Updated the design to treat raw GraphQL request input as the only stable network contract.
- Reduced the stable SDK/CLI surface to GraphQL requests plus local diagnostics and capability inspection.
- Changed legacy high-level CLI command groups from advertised placeholders into explicit boundary-level `UNSUPPORTED` failures.
- Tightened CLI flag validation so invalid `auth-mode`, retry strategy, and numeric inputs no longer fall back silently.

### Session: 2026-03-08 (Architecture Review Continuation)
**Tasks Completed**: Additional progress on TASK-004, TASK-007
**Tasks In Progress**: Mapping backlog and capability-guidance cleanup
**Blockers**: High-level endpoint support still depends on reviewed GraphQL operation artifacts
**Notes**:
- Reviewed the working tree against the GraphQL-only intent and found the stable runtime surface aligned, but the plan/docs still overstated deferred helper support.
- Corrected CLI numeric-flag parsing so malformed integers no longer truncate silently.
- Updated read-only remediation text to point callers at the GraphQL-only contract instead of removed legacy command groups.
- Tightened design docs so only raw GraphQL transport counts as implemented until explicit mappings land.

### Session: 2026-03-08 (CLI Env Precedence Hardening)
**Tasks Completed**: Additional progress on TASK-002, TASK-007
**Tasks In Progress**: Mapping backlog and error-quality validation
**Blockers**: High-level endpoint support still depends on reviewed GraphQL operation artifacts
**Notes**:
- Fixed CLI config assembly so omitted flags no longer override `X_GW_` environment configuration with hard-coded defaults.
- Added regression tests covering env-driven auth-mode and retry behavior through the CLI surface.
- Corrected `.env.example` to match the GraphQL-only contract, valid `X_GW_AUTH_MODE` values, and current GraphQL base URL defaults.

### Session: 2026-03-08 (Command Classification Review)
**Tasks Completed**: Additional progress on TASK-004, TASK-007
**Tasks In Progress**: Mapping backlog and error-quality validation
**Blockers**: High-level endpoint support still depends on reviewed GraphQL operation artifacts
**Notes**:
- Continued review found remaining contract drift: the stable config surface still exposed generic API-base naming and env validation still silently fell back on malformed values.
- Corrective action for the next pass is to rename the stable override to GraphQL-base terminology, validate env/parameter values strictly, and add regression coverage for global CLI flag parsing.

### Session: 2026-03-08 (GraphQL Base Contract Hardening)
**Tasks Completed**: Additional progress on TASK-002, TASK-003, TASK-004, TASK-007
**Tasks In Progress**: Mapping backlog and error-quality validation
**Blockers**: High-level endpoint support still depends on reviewed GraphQL operation artifacts
**Notes**:
- Renamed the stable config/documentation surface from generic API-base terminology to GraphQL-base terminology (`graphqlBaseUrl`, `--graphql-base-url`, `X_GW_GRAPHQL_BASE_URL`).
- Added strict config validation so malformed env or parameter values fail with actionable `VALIDATION_ERROR` instead of silently falling back.
- Closed a CLI error-path leak by validating global flags inside the normal command pipeline and wrapping startup flag parsing in the command error handler.
- Confirmed the GraphQL-only architecture matches the intended stable surface: raw GraphQL request transport, local diagnostics, and capability inspection.
- Fixed a CLI parsing bug where bare non-boolean flags were being coerced to the string `"true"` instead of failing validation.
- Added regression tests for missing required string flag values and bare numeric flags.
- Updated the command spec and implementation plan to record the stricter flag contract and the now-completed SDK surface reduction.
- Reviewed the GraphQL-only CLI surface against the command design and found a classification bug in unsupported-command handling.
- Fixed the router so documented deferred command groups still return `UNSUPPORTED`, while genuine unknown command typos now return `VALIDATION_ERROR` as specified.
- Added a regression test to keep the unknown-vs-deferred command boundary stable in future iterations.

### Session: 2026-03-08 (GraphQL-Base Alias Removal)
**Tasks Completed**: Additional progress on TASK-002, TASK-004, TASK-007
**Tasks In Progress**: Mapping backlog and error-quality validation
**Blockers**: High-level endpoint support still depends on reviewed GraphQL operation artifacts
**Notes**:
- Continued architecture review found remaining contract drift in config alias handling: `apiBaseUrl` and `X_GW_API_BASE_URL` were still accepted despite the GraphQL-base-only design.
- Removed the generic API-base compatibility path from SDK config resolution and CLI flag parsing so the stable surface exposes only `graphqlBaseUrl`, `--graphql-base-url`, and `X_GW_GRAPHQL_BASE_URL`.
- Added CLI unknown-flag validation so deprecated aliases and stray flags now fail with `VALIDATION_ERROR` instead of being ignored.
- Added regression coverage for deprecated alias rejection, health-command global flag validation, and unknown-flag handling.

### Session: 2026-03-08 (GraphQL Response Media-Type Hardening)
**Tasks Completed**: Additional progress on TASK-003, TASK-007
**Tasks In Progress**: Mapping backlog and error-quality validation
**Blockers**: High-level endpoint support still depends on reviewed GraphQL operation artifacts
**Notes**:
- Continued review found a transport-level interoperability bug: response parsing only recognized `application/json`, which breaks GraphQL servers that reply with `application/graphql-response+json` or other `+json` media types.
- Updated the GraphQL transport parser to treat `application/*+json` responses as JSON and added regression coverage for that media-type family.
- Tightened the architecture doc so gateway responsibilities explicitly include GraphQL JSON media-type normalization.

## Related Plans

- **Previous**: None
- **Next**: Split plans may be created by endpoint family if this plan approaches size/task limits
- **Depends On**: design-docs/specs/command.md, design-docs/specs/architecture.md, design-docs/specs/notes.md
