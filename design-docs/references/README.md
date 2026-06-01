# Design References

This directory contains reference materials for system design and implementation.

## External References

| Name | URL | Description |
|------|-----|-------------|
| TypeScript Documentation | https://www.typescriptlang.org/docs/ | Official TypeScript documentation |
| Bun Documentation | https://bun.sh/docs | Official Bun runtime documentation |
| X API Recent Search | https://docs.x.com/x-api/posts/search-recent-posts | Official X recent-search endpoint documentation used for stable direct-reply lookup design |
| rielflow x-follower-ai-business-digest | `/Users/taco/gits/tacogips/rielflow/examples/x-follower-ai-business-digest/workflow.json` | Local behavioral consumer reference for `followingTimeline` via Docker image `ghcr.io/tacogips/x-gateway:latest`; preserves the `followingTimeline` -> `PostPage` -> nullable `metrics.impressionCount` data flow and must not be copied as implementation code. |

## Reference Documents

Reference documents should be organized by topic:

```
references/
├── README.md              # This index file
├── typescript/            # TypeScript patterns and practices
└── <topic>/               # Other topic-specific references
```

## Adding References

When adding new reference materials:

1. Create a topic directory if it does not exist
2. Add reference documents with clear naming
3. Update this README.md with the reference entry
