# X Gateway Adapter Contract Hardening Implementation Plan

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
Harden the restored hybrid architecture by removing code-level contract leaks that still allowed unsupported bearer-posting methods to exist behind a shared adapter interface, and align operator-facing guidance with the current hybrid auth/transport model.

### Scope
**Included**:
- split read vs stable-posting adapter contracts in `src/lib.ts`
- remove stale GraphQL-only operator guidance from checked-in artifacts
- record the hardening pass in design docs and plan tracking

**Excluded**:
- new capability families
- bearer-backed stable posting support
- larger module extraction beyond the current single-file composition

---

## Tasks

### TASK-001: Adapter Contract Split
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.ts` read-adapter and stable-posting-adapter type split

**Completion Criteria**:
- [x] Bearer-backed read adapters no longer define stable posting methods
- [x] OAuth1-backed stable posting remains available through an explicit posting adapter
- [x] Mixed-auth behavior remains unchanged for delivered capabilities

### TASK-002: Operational Guidance Cleanup
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `.env.example`
- `src/x-account-fetch.ts`
- design docs updated for the hardening rule

**Completion Criteria**:
- [x] Checked-in env guidance matches the hybrid stable surface
- [x] Legacy GraphQL-only messaging is removed from repository-owned operator artifacts
- [x] Design docs state that enforced adapter contracts, not latent methods, define capability support

### TASK-003: Validation
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- validation run covering typecheck, tests, and build

**Completion Criteria**:
- [x] Typecheck passes
- [x] Tests pass
- [x] Build passes

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Adapter contract hardening | `src/lib.ts` | COMPLETED | Covered |
| Operator guidance cleanup | `.env.example`, `src/x-account-fetch.ts` | COMPLETED | N/A |
| Design and plan tracking | `design-docs/specs/*.md`, `impl-plans/*` | COMPLETED | N/A |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001, TASK-002 |

## Completion Criteria

- [x] Unsupported bearer-posting paths are removed from the adapter contract
- [x] Repository-owned operator guidance matches the hybrid stable surface
- [x] Validation passes after the hardening changes

## Progress Log

### Session: 2026-03-08 16:10
**Tasks Completed**: TASK-001, TASK-002, TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Reviewed the local continuation work and found the main remaining mismatch was not the high-level architecture but a contract leak: the bearer adapter still exposed posting methods that the stable surface explicitly rejects.
- Split read and posting adapter contracts in `src/lib.ts` so the reviewed OAuth1-only posting rule is enforced by types and construction, not only by runtime guardrails.
- Updated checked-in operator guidance to stop claiming the repository is GraphQL-only now that the stable hybrid baseline is restored.
