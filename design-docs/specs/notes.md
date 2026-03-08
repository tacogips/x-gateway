# Design Notes

This document records additional design constraints and implementation notes.

## Bootstrap Notes

- This repository starts from a PoC baseline at `/g/gits/tacogips/x-sdk-test`.
- PoC artifacts are imported to accelerate implementation, then refined into production architecture.
- Sensitive local environment files may exist only for developer setup and must not be committed unintentionally.
- Environment variable naming is standardized to `X_GW_` prefix for all gateway-specific keys.
- The current delivery baseline is a hybrid capability-adapter model: expose stable intent-level operations first, and keep raw GraphQL as a low-level fallback.
- CLI and SDK surfaces should prefer reviewed adapters over exposing raw X internal GraphQL details as the default product interface.
- Deprecated config aliases should be removed instead of kept as silent compatibility fallbacks when they weaken the stable configuration contract.
- `X_GW_CONFIG_MODE` is the canonical config-resolution variable; `X_GW_AUTH_MODE` must no longer be overloaded with that meaning.
- Capability inventory entries must be conservative about bearer-token support until a reviewed user-context flow exists in code and tests.
- The current stable read/post baseline includes `post.get` plus OAuth1-backed create/delete/reply/quote/repost/unrepost; richer media and article patterns remain explicitly deferred.
- The project-owned GraphQL request contract and capability planner now exist; the next missing slices are additional reviewed capabilities and transport adapters, not another public-contract redesign.
- In mixed-auth shells, reviewed capability adapters must choose auth per capability. Bearer availability must not disable OAuth1-backed stable posting helpers.
- Auth diagnostics must report capability readiness explicitly for the stable baseline; generic auth-family summaries are not enough for AI callers choosing the next command to run.
- Operator-facing examples such as `.env.example` must be treated as part of the product contract; stale GraphQL-only guidance is a design bug because it pushes users toward the wrong auth model.
- Planner diagnostics must name the actual reviewed route, including both transport and auth family, or mixed-auth failures become ambiguous.
- The project-owned GraphQL field registry and the capability registry must be treated as one shared contract boundary with explicit drift checks.
- Stable capability metadata, route planning, and executor dispatch must also be treated as one shared contract boundary with explicit drift checks.

## AI-Caller Expectations

The primary caller is an AI agent. Therefore:

- Errors must avoid vague text such as "request failed".
- Every error must explain:
  - what operation failed
  - probable reason(s)
  - what credentials/scopes might be missing
  - whether retry is useful
  - exact corrective action

## Library Usability Constraints

Library consumers must be able to construct clients like:

- parameter-only configuration (no env vars)
- mixed configuration (parameter overrides env)
- strict mode that rejects missing credentials early

## Coverage Definition Guidance

"All X API features" should be interpreted as:

- all features exposed by targeted API versions and products in scope for this project
- explicit capability table documenting:
  - endpoint/support status
  - required auth mode
  - required scopes/permissions
  - known tier constraints

## Non-Goals for Initial Bootstrap

- immediate implementation of every endpoint in one commit
- undocumented behavior divergence between CLI and SDK
- hidden fallback behavior that masks auth or permission problems

## Deliverable Tracking

Implementation will proceed through implementation plans under `impl-plans/active/`, with progress mirrored in `impl-plans/PROGRESS.json`.
