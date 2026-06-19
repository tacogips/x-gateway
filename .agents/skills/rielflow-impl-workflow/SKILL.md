---
name: rielflow-impl-workflow
description: Use when resolving x-gateway issues through the packaged codex-design-and-implement-review-loop workflow, including accepted design and plan alignment, implementation, review, documentation refresh, verification, commit generation, and push.
---

# Rielflow Implementation Workflow

Use this skill for issue-resolution implementation work in this repository when the user has not explicitly asked to avoid the workflow.

## Workflow Contract

- Workflow id: `codex-design-and-implement-review-loop`
- Workflow mode for bug fixes and feature work: `issue-resolution`
- Planning-only mode: set `workflowInput.executionMode` to `design-plan-only`
- Execution backend references such as `codex-agent` are backend identifiers and must remain explicit in workflow outputs when they are part of the issue context.

The workflow owns intake, design update, implementation-plan creation, implementation, implementation review, user-facing documentation refresh, commit-message generation, commit, and push.

## Documentation Refresh Step

After Step 7 accepts the implementation, Step 8 refreshes user-facing documentation before commit generation.

Mandatory review targets:

- `README.md`
- `.agents/skills/rielflow-impl-workflow/SKILL.md`

Also update directly affected public skills, such as `.agents/skills/x-read-via-reader/SKILL.md`, when a shipped behavior changes the recommended user-facing command surface.

## followingTimeline Documentation Rule

For the accepted owner-only metrics fix, user-facing documentation must state that `followingTimeline(...)` followed-account fanout:

- requests public tweet fields for followed-user timelines
- keeps `public_metrics`
- does not request owner-only `organic_metrics` or `promoted_metrics` for other users
- preserves stable nullable `metrics.impressionCount` semantics
- remains a bounded project-owned aggregate over followed accounts, not a raw X home timeline cursor

The downstream reference `../rielflow/examples/x-follower-ai-business-digest/workflow.json` is a behavioral consumer reference only. Do not copy implementation code from that repository.

## Verification Commands

Documentation-refresh outputs should keep the accepted verification explicit:

```bash
bun run typecheck
bun test
bun run build
bun run format:check
git diff --check
```
