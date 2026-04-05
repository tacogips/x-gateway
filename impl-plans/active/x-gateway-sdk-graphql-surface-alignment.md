# X Gateway SDK GraphQL Surface Alignment Plan

**Status**: Completed
**Design Reference**: `design-docs/specs/architecture.md#overview`, `design-docs/specs/design-public-graphql-contract.md#contract-rules`, `design-docs/specs/design-graphql-command-surface.md`
**Created**: 2026-04-05
**Last Updated**: 2026-04-05

## Summary

Align the programmatic SDK surface with the shipped `graphql` public contract after the CLI namespace rename.

The repository already exposes `graphql query` as the canonical CLI entrypoint, but the SDK and internal planner names still used stale `api request` terminology. This plan removes that drift so the public GraphQL contract uses one consistent name across CLI, SDK, code, and documentation.

## Scope

**Included**:
- SDK method rename from `apiRequest(...)` to `graphqlQuery(...)`
- type and helper renames that still described the project-owned GraphQL contract as `api request`
- planner module rename to `src/public-graphql-contract.ts`
- regression coverage and design/progress updates for the renamed SDK surface

**Excluded**:
- new GraphQL fields or capability families
- compatibility aliases for removed SDK names
- live upstream behavior changes

## Modules

### 1. SDK Surface

#### `src/lib.ts`

```typescript
type XGatewayClient = Readonly<{
  graphqlQuery: (
    options: XGatewayGraphqlQueryOptions,
  ) => Promise<Readonly<{ data: Readonly<Record<string, unknown>> }>>;
}>;
```

**Checklist**:
- [x] Canonical SDK helper is named `graphqlQuery`
- [x] Stale `apiRequest` type names are removed from the public SDK surface

### 2. Public GraphQL Planner Naming

#### `src/public-graphql-contract.ts`

```typescript
export function createPublicGraphqlQueryPlan(
  input: PublicGraphqlQueryInput,
  createValidationError: ValidationErrorFactory,
  createPayloadError: PayloadErrorFactory,
): PlannedPublicGraphqlQuery;
```

**Checklist**:
- [x] Planner module/file name matches the owned GraphQL contract terminology
- [x] Internal planner types use `GraphqlQuery` naming instead of stale `ApiRequest` naming

### 3. Verification and Design Sync

#### `src/cli.ts`
#### `src/lib.test.ts`
#### `design-docs/specs/architecture.md`
#### `design-docs/specs/design-public-graphql-contract.md`

**Checklist**:
- [x] CLI dispatch uses the renamed SDK helper
- [x] Regression tests assert `graphqlQuery` is present and `apiRequest` is absent
- [x] Design docs describe the canonical SDK helper name
- [x] `bun test`, `bun run typecheck`, and `bun run build` pass

## Completion Criteria

- [x] SDK naming matches the GraphQL-first public design
- [x] Stale `api request` naming is removed from code touched by the public GraphQL path
- [x] Planner module/path naming matches the owned GraphQL contract
- [x] Tests and build verification pass

## Progress Log

### Session: 2026-04-05 18:05 JST
**Tasks Completed**: TASK-001, TASK-002
**Tasks In Progress**: None
**Blockers**: None
**Notes**:
- Architecture review found a real naming mismatch: the CLI had already standardized on `graphql`, but the SDK still exposed `apiRequest(...)` and the planner module still used `public-api-contract` naming.
- Renamed the SDK helper to `graphqlQuery(...)`, renamed the planner module and related internal types to `public-graphql-contract` / `GraphqlQuery`, updated docs and progress tracking, and re-ran automated verification.
