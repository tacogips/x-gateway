# X Gateway Hybrid Capability Adapters Implementation Plan

**Status**: Completed
**Design Reference**: design-docs/specs/architecture.md#stable-contract-with-internal-adapters
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
Restore the intended product shape by keeping stable capability-oriented CLI/SDK surfaces as the primary contract, selecting REST or GraphQL internally per capability, and leaving `graphql request` as an explicit low-level escape hatch rather than the default public interface.

### Scope
**Included**:
- internal capability-adapter boundary for live operations
- OAuth1-compatible identity and posting restoration
- capability inventory updates for hybrid transport strategy
- command/docs alignment for `account me`, `post create`, and config-mode naming

**Excluded**:
- full parity for every legacy command group in one iteration
- undocumented/private GraphQL mappings without reviewed artifacts
- media, article, DM, and social-graph completion in this plan

---

## Tasks

### TASK-001: Capability Adapter Boundary
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.ts` internal capability adapter abstraction separating high-level operations from raw GraphQL transport
- adapter selection based on configured auth mode

**Completion Criteria**:
- [x] Raw GraphQL transport remains isolated from higher-level capability methods
- [x] High-level methods dispatch through an internal adapter boundary
- [x] Adapter selection is auth-aware

### TASK-002: OAuth1-Compatible Identity and Post Baseline
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/lib.ts` auth-appropriate `accountMe` implementation
- `src/lib.ts` stable text-post implementation
- `src/lib.test.ts` regression coverage for OAuth1 and bearer account/profile lookup

**Completion Criteria**:
- [x] OAuth1 identity lookup avoids bearer-only assumptions
- [x] Simple text post works through the hybrid adapter path
- [x] OAuth1 and bearer account/profile flows are covered by tests

### TASK-003: Command and Config Contract Alignment
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/cli.ts` stable command exposure for implemented capability adapters
- `.env.example` and design docs aligned on `X_GW_CONFIG_MODE`

**Completion Criteria**:
- [x] CLI usage reflects restored stable commands
- [x] Canonical config-mode naming is documented
- [x] Deprecated alias handling remains explicit and tested

### TASK-004: Error Mapping for Adapter Operations
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- normalized upstream error handling for REST-backed capability adapters
- actionable auth/scope diagnostics preserved across adapter transports

**Completion Criteria**:
- [x] OAuth/authz/rate-limit failures are normalized consistently for adapter operations
- [x] Adapter-level error messages identify the capability and likely remediation
- [x] Tests cover representative adapter failure mapping

### TASK-005: Posting Expansion
**Status**: Completed
**Parallelizable**: No (depends on TASK-001 and TASK-004)
**Deliverables**:
- reply, quote, repost/unrepost operations
- request/response contracts for stable post patterns
- capability inventory updates for supported posting variants

**Completion Criteria**:
- [x] Reply support implemented
- [x] Quote support implemented or explicitly documented as blocked
- [x] Repost/undo repost support implemented or explicitly documented as blocked

### TASK-006: Read Capability Expansion
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- prioritized read adapters beyond `account me`
- documented transport/auth matrix for each newly restored read capability

**Completion Criteria**:
- [x] At least one additional high-value read capability is restored
- [x] Capability inventory distinguishes REST-backed vs GraphQL-backed reads
- [x] Unsupported reads continue to fail with clear remediation

### TASK-007: Verification and Documentation
**Status**: Completed
**Parallelizable**: No (depends on TASK-002, TASK-003, TASK-004)
**Deliverables**:
- typecheck/test/build validation
- implementation plan progress updates
- design docs updated to match delivered behavior

**Completion Criteria**:
- [x] Typecheck passes
- [x] Test suite passes
- [x] Build passes
- [x] Design docs reflect the hybrid contract
- [x] Remaining backlog is documented without overstating support

---

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Capability adapter composition | `src/lib.ts` | COMPLETED | Partial |
| CLI contract alignment | `src/cli.ts` | COMPLETED | Partial |
| Capability inventory docs | `design-docs/specs/*.md` | COMPLETED | N/A |
| Adapter error normalization | `src/lib.ts` | COMPLETED | Covered |
| Expanded posting/read adapters | `src/lib.ts` | COMPLETED | Covered |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-004 | TASK-001 |
| TASK-005 | TASK-001, TASK-004 |
| TASK-007 | TASK-002, TASK-003, TASK-004 |

## Completion Criteria

- [x] Stable capability-oriented CLI/SDK contract restored for prioritized operations
- [x] Raw GraphQL retained as an explicit low-level surface, not the only practical live path
- [x] OAuth1-compatible workflows restored for the first-priority capabilities
- [x] Capability inventory and docs accurately describe transport and auth limitations
- [x] Tests and type checks pass for delivered scope

## Progress Log

### Session: 2026-03-08 11:30
**Tasks Completed**: TASK-001, TASK-002, TASK-003 (initial slice), TASK-007 (partial)
**Tasks In Progress**: TASK-004, TASK-007
**Blockers**: None
**Notes**:
- Replaced the stale GraphQL-only product decision in the design docs with a hybrid capability-adapter model.
- Extracted an internal capability-adapter boundary in `src/lib.ts` so high-level operations no longer share the raw GraphQL transport path directly.
- Routed OAuth1 `account me` through `v1.verifyCredentials()` and kept bearer identity lookup on `v2.me()`.
- Revalidated `bun run typecheck`, `bun test`, and `bun run build`.

### Session: 2026-03-08 12:20
**Tasks Completed**: TASK-004, TASK-007
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Added capability-aware adapter error normalization so REST-backed failures name the failed operation, transport, and remediation path instead of surfacing only generic upstream errors.
- Tightened the delivered contract to avoid overstating support: `post.create` is now documented as simple text posting only, and low-level GraphQL is described consistently as an escape hatch rather than the primary product surface.
- Revalidated `bun run typecheck`, `bun test`, and `bun run build` after the adapter error-layer changes.

### Session: 2026-03-08 12:40
**Tasks Completed**: TASK-003, TASK-007
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Corrected a contract mismatch in the first hybrid slice: `post.create` had been advertised as bearer-capable even though the reviewed stable path is OAuth1-only.
- Added explicit capability transport metadata to the runtime registry so the code matches the inventory design and callers can distinguish `graphql-web`, `rest-v2`, and `hybrid` rows.
- Added regression coverage for bearer rejection on stable post creation and for tightened capability metadata.

### Session: 2026-03-08 13:20
**Tasks Completed**: TASK-005
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Expanded the stable OAuth1 posting baseline to include reply, quote, repost, and unrepost operations through reviewed REST-backed adapters.
- Fixed a CLI contract bug where `x-gateway-reader` usage text incorrectly advertised write commands despite runtime enforcement rejecting them.
- Updated design docs and capability inventory to reflect the expanded posting baseline without overstating bearer-token support.

### Session: 2026-03-08 14:10
**Tasks Completed**: TASK-006
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Restored `post.get` as a stable read capability through the public v2 lookup API with author and referenced-post expansion.
- Fixed a read-surface bug in `x-gateway-reader`: it now allows `post get` while continuing to reject write-oriented post commands.
- Completed the first hybrid plan iteration with CLI, SDK, tests, and docs aligned on the delivered read/post baseline.
