# X Gateway Capability Planner Separation Implementation Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#stable-contract-with-internal-adapters`
**Created**: 2026-03-08
**Last Updated**: 2026-03-08

---

## Design Document Reference

**Source**:
- `design-docs/specs/architecture.md`
- `design-docs/specs/design-public-graphql-contract.md`
- `design-docs/specs/design-api-inventory.md`

### Summary
The repository already restored a hybrid stable surface, but the public request contract, capability mapping, and auth/transport routing are still too tightly coupled inside one implementation path. This plan hardens the intended three-layer model by introducing explicit registry-driven planning artifacts before broader capability expansion continues.

### Scope
**Included**:
- explicit public GraphQL field registry owned by `x-gateway`
- explicit capability route planning metadata for current stable capabilities
- refactor of stable request execution to use the planner artifacts
- regression coverage for the planner-driven path

**Excluded**:
- new network capability families beyond the current stable baseline
- `likes.list` adapter implementation
- media/article/timeline/social-graph execution work
- physical extraction into `src/public-contract/` or `src/planner/` modules

---

## Tasks

### TASK-001: Public Field Registry
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/lib.ts` project-owned public GraphQL field registry
- argument-to-capability input mapping per stable field
- result normalization metadata per stable field

**Completion Criteria**:
- [x] Public GraphQL fields no longer resolve capability ids implicitly from the capability registry
- [x] Field-specific argument mapping is explicit in one registry artifact
- [x] Field-specific response shaping is explicit in one registry artifact

### TASK-002: Capability Route Planner
**Status**: Completed
**Parallelizable**: No (depends on TASK-001)
**Deliverables**:
- `src/lib.ts` capability execution planning helpers for read and stable posting flows
- explicit auth-family and transport selection per planned capability execution

**Completion Criteria**:
- [x] Stable reads route through an explicit planner step
- [x] Stable posting routes through an explicit planner step
- [x] Auth selection is capability-specific and no longer hidden behind a generic preferred-adapter helper

### TASK-003: Verification and Documentation
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- updated design docs reflecting registry-driven planning
- regression validation for planner-driven execution

**Completion Criteria**:
- [x] Architecture and contract docs describe separate public-field and route-planner responsibilities
- [x] Typecheck passes
- [x] Test suite passes
- [x] Remaining extraction work is documented without overstating current modularity

### TASK-004: Follow-On Extraction Backlog
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- follow-on backlog notes for extraction into dedicated planner/public-contract modules
- next-slice dependencies for likes/media capability work

**Completion Criteria**:
- [x] Follow-on extraction boundary is documented
- [x] Next capability-expansion work references the hardened planner baseline

---

## Module Status

| Module | Path | Status | Tests |
|--------|------|--------|-------|
| Public field registry | `src/lib.ts` | COMPLETED | Pending |
| Capability route planner | `src/lib.ts` | COMPLETED | Pending |
| Design sync | `design-docs/specs/*.md` | COMPLETED | N/A |
| Follow-on extraction backlog | `impl-plans/active/x-gateway-capability-planner-separation.md` | COMPLETED | N/A |

## Dependencies

| Task | Depends On |
|------|------------|
| TASK-002 | TASK-001 |
| TASK-003 | TASK-001, TASK-002 |
| TASK-004 | TASK-003 |

## Completion Criteria

- [x] Public GraphQL field mapping is explicit and project-owned
- [x] Capability execution routing is explicit for the stable baseline
- [x] Verification passes after the planner refactor
- [x] Remaining extraction and expansion work is tracked clearly

## Progress Log

### Session: 2026-03-08 15:10
**Tasks Completed**: TASK-001, TASK-002 (initial slice)
**Tasks In Progress**: TASK-003
**Blockers**: None
**Notes**:
- Architecture review found that the current code already matches the product direction at a high level, but the planning boundary remained implicit because public field mapping and capability routing were embedded in one switch path.
- Added a project-owned public field registry and explicit capability route planners so auth-family plus transport selection now happens as a first-class planning step.
- Kept the implementation collocated in `src/lib.ts` for this iteration while documenting the remaining extraction backlog.

### Session: 2026-03-08 15:25
**Tasks Completed**: TASK-003
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Revalidated the planner refactor with `bun run typecheck`, `bun run test`, and `bun run build`.
- Added mixed-auth regression coverage proving the public GraphQL contract still routes `accountMe` and `createPost` through capability-specific reviewed paths instead of defaulting blindly to bearer auth.

### Session: 2026-03-08 21:10
**Tasks Completed**: TASK-004
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- The planner/public-contract split is now documented as the baseline for follow-on capability work rather than a future aspiration.
- The next slice restores `likes.list` through that same baseline instead of adding a separate GraphQL-first path.
