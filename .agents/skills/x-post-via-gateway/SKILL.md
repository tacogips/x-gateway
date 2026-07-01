---
name: x-post-via-gateway
description: Use when writing to X/Twitter with x-gateway-writer. Covers auth preflight, schema inspection, and project-owned GraphQL mutations such as createPost, quotePost, repostPost, unrepostPost, replyToPost, deletePost, likes, Lists, and DMs. Do not use x-gateway-reader for mutations.
allowed-tools: Read, Grep, Glob, Bash
---

# X Post Via Gateway

Use this skill when the task is to publish or mutate X state.

## Binary

Use `x-gateway-writer`.

Do not use `x-gateway-reader` for writes. That binary is read-only and rejects mutations.

## Workflow

1. Run `x-gateway-writer auth verify` when auth readiness is relevant.
2. Run `x-gateway-writer graphql schema` if you need to confirm the current mutation signatures.
3. Use `x-gateway-writer graphql query '<graphql>'` for reviewed project-owned mutations.
4. Use `--json` when another agent or tool will parse the result.

## Posting Operations

Create a post:

```bash
x-gateway-writer graphql query 'mutation { createPost(text: "hello world") { id text } }'
```

Quote a post:

```bash
x-gateway-writer graphql query 'mutation { quotePost(text: "commentary", quotedPostId: "123") { id text } }'
```

Repost a post:

```bash
x-gateway-writer graphql query 'mutation { repostPost(postId: "123") { id reposted } }'
```

Undo a repost:

```bash
x-gateway-writer graphql query 'mutation { unrepostPost(postId: "123") { id reposted } }'
```

Reply to a post:

```bash
x-gateway-writer graphql query 'mutation { replyToPost(text: "reply text", replyToPostId: "123") { id text } }'
```

Delete a post:

```bash
x-gateway-writer graphql query 'mutation { deletePost(postId: "123") { id deleted } }'
```

Like a post:

```bash
x-gateway-writer graphql query 'mutation { likePost(postId: "123") { id liked } }'
```

Create or update a List:

```bash
x-gateway-writer graphql query 'mutation { createList(name: "x-gateway", private: true) { id name } }'
```

```bash
x-gateway-writer graphql query 'mutation { updateList(listId: "123", description: "updated") { id updated } }'
```

Send a Direct Message:

```bash
x-gateway-writer graphql query 'mutation { createDirectMessage(participantId: "123", text: "hello") { id eventType conversationId } }'
```

Send a Direct Message with a local media attachment:

```bash
x-gateway-writer graphql query 'mutation { createDirectMessage(participantId: "123", text: "hello", attachments: [{ kind: "image", filePath: "./image.gif" }]) { id eventType conversationId attachmentMediaKeys } }'
```

Lower-level OpenAPI parity mutations return `OpenAPIResult { ok payload }`:

```bash
x-gateway-writer graphql query 'mutation { createComplianceJob(type: "tweets", name: "audit") { ok payload } }'
```

```bash
x-gateway-writer graphql query 'mutation { initializeMediaUpload(mediaType: "image/png", totalBytes: 1024) { ok payload } }'
```

## Attachment Pattern

For image-backed mutations, use the project-owned attachment input. Tweet
attachments prefer OAuth2 bearer credentials with `media.write` and fall back to
OAuth1 when no bearer token is configured:

```bash
x-gateway-writer graphql query 'mutation { createPost(text: "hello", attachments: [{ kind: "image", filePath: "./image.png", altText: "example" }]) { id text } }'
```

The same attachment pattern applies to `createPost`, `replyToPost`, and `quotePost`.

## Guardrails

- For read-only retrieval tasks, prefer the `x-read-via-reader` skill and `x-gateway-reader`.
- If a mutation fails validation, inspect `x-gateway-writer graphql schema` and correct the request to match the public schema.
- Use canonical argument names such as `postId`, `quotedPostId`, and `replyToPostId`.
- DM writes can fail with upstream 403 when the app/token/recipient relationship does not permit messages; do not claim a DM was sent unless the mutation returns an event id.
- DM attachments use OAuth2 bearer credentials with `media.write`, upload local
  files with the DM media category (`dm_gif`, `dm_image`, or `dm_video`), and
  then send the resulting `media_id` in the DM message body.
- OpenAPI parity writes include compliance jobs, Community Notes, reply hiding,
  DM block/unblock, media one-shot upload, media upload
  initialization/append/finalization/metadata/subtitles,
  user public-key registration, webhooks, activity/account-activity
  subscriptions, encrypted Chat primitives, and Chat media upload
  initialization/append/finalization.
- `sendEncryptedChatMessage` is a raw Chat API primitive and requires encoded
  encrypted message fields. Use `createDirectMessage` for normal plaintext DM
  sending.
- Spaces, streaming, and stream connection management are intentionally not
  written through this skill.
