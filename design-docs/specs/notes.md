# Design Notes

This document records additional design constraints and implementation notes.

## Bootstrap Notes

- This repository starts from a PoC baseline at `/g/gits/tacogips/x-sdk-test`.
- PoC artifacts are imported to accelerate implementation, then refined into production architecture.
- Sensitive local environment files may exist only for developer setup and must not be committed unintentionally.

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
