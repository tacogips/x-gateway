# X API Capability Inventory Design

This document defines how `x-gateway` tracks and implements broad X API capability coverage.

## Goal

Provide an explicit, auditable inventory for API support so "full coverage" is measurable instead of implicit.

The inventory must distinguish between:

- raw GraphQL transport support
- reviewed GraphQL operation mappings
- high-level convenience helpers built on top of those mappings
- intentionally deferred helper surfaces that must remain rejected at the boundary

## Coverage Definition

Coverage is evaluated per capability row with these states:

- `implemented`
- `planned`
- `blocked_by_plan`
- `blocked_by_scope`
- `unsupported`

A row cannot be marked `implemented` unless all required checks (contract tests, error mapping, auth validation) pass.

Current repository-state rule:

- Only `graphql.request` may be treated as implemented without a higher-level mapping artifact.
- Non-raw capability families must remain `planned` or `blocked_by_plan` until their concrete GraphQL documents/variables are committed and reviewed.

## Capability Registry Schema

Each capability entry must track:

- capability id
- endpoint family
- operation
- auth mode (`oauth1`, `oauth2`, `bearer`, mixed)
- required scopes/permissions
- required API tier/plan (if applicable)
- request/response type mapping status
- CLI command mapping
- SDK method mapping
- error coverage status
- test coverage status
- notes/limitations

## Endpoint Families (Design Baseline)

- raw GraphQL request transport
- authentication and identity
- users and profiles
- tweets/posts lifecycle
- timelines and mentions
- follows and social graph
- likes and bookmarks
- media upload and attachment
- engagement actions (repost/undo, like/unlike)
- direct messages (where scope allows)
- search/discovery surfaces (where scope allows)

## Posting Pattern Matrix

The posting subsystem must implement these patterns as first-class operations:

- normal text post
- reply post with parent id
- quote post with quoted post id
- repost and undo repost
- media post (single/multi image)
- media post (video)
- article/long-form publish path when API surface supports it
- referenced-content retrieval for quote/reply/repost source tracing

For each pattern, design must define:

- required inputs
- optional inputs
- auth and scope requirements
- output contract
- error classes and user guidance

## Error-Quality Acceptance Criteria

For every capability, at least these failure classes must be mapped:

- missing credentials
- expired credentials
- revoked/invalid credentials
- insufficient permissions/scopes
- rate-limit/quota exhaustion
- invalid request payload
- resource not found
- upstream/transport failure

Error output must include probable cause and recovery guidance.

## Verification Requirements

A capability reaches `implemented` only when:

- raw transport capability exists if the capability depends on GraphQL execution
- concrete GraphQL operation id/query and variable contract are documented
- SDK method exists with typed request/response
- CLI command path is wired (if capability is CLI-exposed)
- unit test coverage exists for payload and error mapping
- integration or contract test exists for representative API response shapes
- docs entry updated in capability registry

If any of the above is missing:

- the capability must remain non-implemented in the registry
- the CLI must not advertise the command as generally usable
- the SDK must not expose it as part of the stable public contract

## Initial Implementation Sequence

1. define registry artifact format (`design-docs/specs` + generated machine-readable index)
2. implement posting and media capabilities first
3. implement timeline/user/social capabilities
4. implement remaining scoped capabilities and mark explicit limitations

## References

- `design-docs/specs/command.md`
- `design-docs/specs/architecture.md`
- `design-docs/specs/notes.md`
