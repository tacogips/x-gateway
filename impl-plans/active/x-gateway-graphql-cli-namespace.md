# X Gateway GraphQL CLI Namespace Plan

**Status**: In Progress
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
**Status**: In Progress
**Parallelizable**: No
**Deliverables**:
- `src/cli.ts`
- `src/lib.test.ts`

**Completion Criteria**:
- [ ] `graphql query <query>` executes the owned GraphQL contract
- [ ] `graphql schema` prints the owned GraphQL schema
- [ ] `api request --query ...` fails with migration guidance
- [ ] `schema print` fails with migration guidance
- [ ] reader mode still rejects mutations through `graphql query`

### TASK-002: Verification
**Status**: Not Started
**Parallelizable**: Yes
**Deliverables**:
- `src/lib.test.ts`

**Completion Criteria**:
- [ ] `bun run typecheck` passes
- [ ] `bun test` passes
- [ ] `bun run build` passes

## Progress Log

### Session: 2026-04-05 16:35 JST
**Tasks Completed**: None yet
**Tasks In Progress**: TASK-001
**Blockers**: None
**Notes**:
- The public namespace is being normalized so the CLI says `graphql` where it already means the owned project contract.
