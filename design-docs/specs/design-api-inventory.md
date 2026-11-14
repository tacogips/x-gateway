# X API Capability Inventory Design

This document defines how `x-gateway` tracks and implements broad X API capability coverage.

## Goal

Provide an explicit, auditable inventory for API support so "full coverage" is measurable instead of implicit.

The inventory must distinguish between:

- reviewed project-owned GraphQL field coverage
- reviewed REST-backed capability adapters
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

- A capability may be treated as implemented when it has a reviewed adapter contract, matching tests, and documented auth/transport constraints.
- Implemented capabilities may use REST, GraphQL, or a hybrid composition internally.
- Unreachable placeholder methods inside an adapter for the wrong auth family do not count toward implementation status; the adapter boundary itself must enforce the reviewed auth contract.
- Capability families must remain `planned` or `blocked_by_plan` until their concrete adapter contract is committed and reviewed.
- Auth metadata must reflect the reviewed path actually implemented in the repository, not hypothetical upstream support.

## Capability Registry Schema

Each capability entry must track:

- capability id
- public operation name
- endpoint family
- operation
- read/write classification
- transport strategy (`rest-v1`, `rest-v2`, `graphql-web`, `hybrid`)
- preferred transport
- fallback transport if any
- auth mode (`oauth1`, `oauth2`, `bearer`, mixed)
- required scopes/permissions
- required API tier/plan (if applicable)
- request/response type mapping status
- public-field mapping status
- capability-route planning status
- CLI command mapping
- SDK method mapping
- error coverage status
- test coverage status
- notes/limitations

## Endpoint Families (Design Baseline)

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

- required transport capability exists
- GraphQL-backed capabilities have concrete operation id/query and variable contract documented
- REST-backed capabilities have concrete endpoint and auth contract documented
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
2. restore the highest-value stable adapters first (`auth.verify`, `account.me`, `post.get`, `post.replies`, `post.create`, `post.delete`, `post.reply`, `post.quote`, `post.repost`, `post.unrepost`), while keeping `likes.list` deferred until a reviewed live route is verified
3. add a project-owned public GraphQL contract that maps those public fields onto the same reviewed capabilities
4. expand posting and read capabilities where REST-backed adapters are reliable
5. add GraphQL-backed adapters only for capabilities that cannot be covered cleanly by the public REST surface
6. implement remaining scoped capabilities and mark explicit limitations

## References

- `design-docs/specs/command.md`
- `design-docs/specs/architecture.md`
- `design-docs/specs/notes.md`
- `design-docs/specs/design-public-graphql-contract.md`
