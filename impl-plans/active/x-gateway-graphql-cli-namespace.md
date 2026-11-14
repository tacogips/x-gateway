# X Gateway GraphQL CLI Namespace Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/design-graphql-command-surface.md`, `design-docs/specs/command.md#project-owned-graphql-contract`
**Created**: 2026-04-05
**Last Updated**: 2026-04-05

---

## Summary

Rename the public CLI entrypoint for the owned GraphQL contract from `api request --query <graphql>` to `graphql query <query>` and rename schema printing from `schema print` to `graphql schema`.

## Scope

**Included**:
- public CLI namespace change to `graphql query <query>` and `graphql schema`
- migration diagnostics for removed `api request` and `schema print` shapes
- regression coverage for the renamed command surface

**Excluded**:
- SDK method renames
- changes to the owned GraphQL schema itself
- new GraphQL fields or capability additions

## Tasks

### TASK-001: Public Command Rename
**Status**: Completed
**Parallelizable**: No
**Deliverables**:
- `src/cli.ts`
- `src/lib.test.ts`

**Completion Criteria**:
- [x] `graphql query <query>` executes the owned GraphQL contract
- [x] `graphql schema` prints the owned GraphQL schema
- [x] `api request --query ...` fails with migration guidance
- [x] `schema print` fails with migration guidance
- [x] reader mode still rejects mutations through `graphql query`

### TASK-002: Verification
**Status**: Completed
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`

**Completion Criteria**:
- [x] `bun run typecheck` passes
- [x] `bun test` passes
- [x] `bun run build` passes

## Progress Log

### Session: 2026-04-05 16:35 JST
**Tasks Completed**: None yet
**Tasks In Progress**: TASK-001
**Blockers**: None
**Notes**:
- The public namespace is being normalized so the CLI says `graphql` where it already means the owned project contract.

### Session: 2026-04-05 17:20 JST
**Tasks Completed**: TASK-001, TASK-002
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Continuation review found one leftover legacy CLI acceptance path (`--days`) and one larger coherence bug: the repository still advertised `graphql.request` as an implemented capability even though the renamed public surface no longer exposes any raw upstream GraphQL entrypoint.
- Removed the stale raw-GraphQL capability/inventory/readiness claims, tightened the supported CLI flag set, updated public design docs to match the shipped `graphql query` contract, and re-ran `bun test`, `bun run typecheck`, and `bun run build`.
