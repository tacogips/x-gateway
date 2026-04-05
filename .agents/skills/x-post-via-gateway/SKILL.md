---
name: x-post-via-gateway
description: Use when writing to X/Twitter with x-gateway. Covers auth preflight, schema inspection, and project-owned GraphQL mutations such as createPost, quotePost, repostPost, unrepostPost, replyToPost, and deletePost. Do not use x-gateway-reader for mutations.
allowed-tools: Read, Grep, Glob, Bash
---

# X Post Via Gateway

Use this skill when the task is to publish or mutate X state.

## Binary

Use `x-gateway`.

Do not use `x-gateway-reader` for writes. That binary is read-only and rejects mutations.

## Workflow

1. Run `x-gateway auth verify` when auth readiness is relevant.
2. Run `x-gateway graphql schema` if you need to confirm the current mutation signatures.
3. Use `x-gateway graphql query '<graphql>'` for reviewed project-owned mutations.
4. Use `--json` when another agent or tool will parse the result.

## Posting Operations

Create a post:

```bash
x-gateway graphql query 'mutation { createPost(text: "hello world") { id text } }'
```

Quote a post:

```bash
x-gateway graphql query 'mutation { quotePost(text: "commentary", quotedPostId: "123") { id text } }'
```

Repost a post:

```bash
x-gateway graphql query 'mutation { repostPost(postId: "123") { id reposted } }'
```

Undo a repost:

```bash
x-gateway graphql query 'mutation { unrepostPost(postId: "123") { id reposted } }'
```

Reply to a post:

```bash
x-gateway graphql query 'mutation { replyToPost(text: "reply text", replyToPostId: "123") { id text } }'
```

Delete a post:

```bash
x-gateway graphql query 'mutation { deletePost(postId: "123") { id deleted } }'
```

## Attachment Pattern

For image-backed mutations, use the project-owned attachment input:

```bash
x-gateway graphql query 'mutation { createPost(text: "hello", attachments: [{ kind: "image", filePath: "./image.png", altText: "example" }]) { id text } }'
```

The same attachment pattern applies to `createPost`, `replyToPost`, and `quotePost`.

## Guardrails

- For read-only retrieval tasks, prefer the `x-read-via-reader` skill and `x-gateway-reader`.
- If a mutation fails validation, inspect `x-gateway graphql schema` and correct the request to match the public schema.
- Use canonical argument names such as `postId`, `quotedPostId`, and `replyToPostId`.
