# GraphQL Command Surface Design

This document defines the public CLI namespace for the project-owned GraphQL contract.

## Overview

The public CLI surface should expose the owned GraphQL contract directly instead of wrapping it in an extra `api request` layer.

Target commands:

```bash
x-gateway graphql query '<query>'
x-gateway graphql schema
x-gateway-reader graphql query '<query>'
x-gateway-reader graphql schema
```

## Design Goals

- Make the public contract obvious from the command name.
- Remove the redundant `api request --query` wrapper.
- Keep `x-gateway-reader` query-only by rejecting GraphQL mutations at the command boundary.
- Avoid implying direct access to upstream X web GraphQL.

## Public Semantics

- `graphql query <query>` executes the project-owned `x-gateway` GraphQL contract.
- `graphql schema` prints the project-owned GraphQL schema exposed by this repository.
- The positional `<query>` argument is required and should be passed as a single shell-quoted argument.
- The public `graphql` namespace does not expose upstream GraphQL transport parameters or persisted-query concepts.
- The SDK should use matching terminology via `createXGatewayClient().graphqlQuery({ query })`.

## Migration

Previous public forms:

```bash
x-gateway api request --query '<query>'
x-gateway-reader api request --query '<query>'
x-gateway schema print
x-gateway-reader schema print
```

New canonical forms:

```bash
x-gateway graphql query '<query>'
x-gateway-reader graphql query '<query>'
x-gateway graphql schema
x-gateway-reader graphql schema
```

Migration diagnostics should point callers from the old forms to the new forms.

## Reader Rules

- `x-gateway-reader graphql query '<query>'` must reject mutations.
- `x-gateway-reader graphql schema` remains allowed because it is local introspection.

## Verification Targets

- Usage output shows `graphql query <query>` and `graphql schema`.
- `api request --query ...` is no longer the public entrypoint.
- `schema print` is no longer the public entrypoint.
- CLI tests cover successful query execution, schema printing, reader-mode mutation blocking, and migration diagnostics.

## References

See `design-docs/specs/command.md` and `design-docs/specs/architecture.md`.
