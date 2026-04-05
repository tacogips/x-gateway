---
name: x-read-via-reader
description: Use when reading data from X/Twitter with x-gateway-reader. Covers auth preflight, schema inspection, and read-only project-owned GraphQL queries such as account lookup, post lookup, search, timelines, and usage. Do not use for posting or other mutations.
allowed-tools: Read, Grep, Glob, Bash
---

# X Read Via Reader

Use this skill when the task is to inspect or retrieve X data without performing writes.

## Binary

Use `x-gateway-reader`.

This binary is read-only. It must not be used for `createPost`, `quotePost`, `repostPost`, or any other mutation.

## Workflow

1. Run `x-gateway-reader auth verify` when auth readiness is relevant.
2. Run `x-gateway-reader graphql schema` if you need to confirm the current public GraphQL contract.
3. Prefer `x-gateway-reader graphql query '<graphql>'` for reviewed read operations.
4. Use `--json` when another agent or tool will parse the result.

## Read Operations

Prefer the project-owned GraphQL surface instead of ad hoc legacy commands.

Common queries:

```bash
x-gateway-reader graphql query 'query { accountMe { id username name } }'
```

```bash
x-gateway-reader graphql query 'query { post(id: "123") { id text author { username } referencedPosts { id relation } } }'
```

```bash
x-gateway-reader graphql query 'query { post(id: "123") { id text replies(maxResults: 10) { posts { id text replies(maxResults: 10) { pageInfo { resultCount } } } pageInfo { resultCount } } } }'
```

```bash
x-gateway-reader graphql query 'query { searchPosts(query: "openai", maxResults: 5) { posts { id text author { username } } pageInfo { resultCount nextToken } } }'
```

```bash
x-gateway-reader graphql query 'query { homeTimeline(maxResults: 10) { posts { id text } pageInfo { resultCount nextToken } } }'
```

```bash
x-gateway-reader graphql query 'query { userTimeline(userId: "user-42", maxResults: 10) { posts { id text } pageInfo { resultCount nextToken } } }'
```

```bash
x-gateway-reader graphql query 'query { mentionsTimeline(userId: "user-42", maxResults: 10) { posts { id text } pageInfo { resultCount nextToken } } }'
```

```bash
x-gateway-reader graphql query 'query { apiUsage(days: 14) { projectId projectUsage dailyProjectUsage { usage { date usage } } } }'
```

## Guardrails

- If the user asks to post, repost, quote, reply, delete, or otherwise mutate X state, stop using this skill and switch to the `x-post-via-gateway` skill.
- If a query fails validation, inspect `x-gateway-reader graphql schema` and rewrite the request to match the public schema.
- Prefer stable project-owned GraphQL fields over raw upstream GraphQL shapes.
