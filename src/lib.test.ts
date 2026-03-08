import { afterEach, describe, expect, test, vi } from "vitest";
import { executeCli } from "./cli";
import { STABLE_CAPABILITY_IDS } from "./capability-metadata";
import {
  computeBackoffDelayMs,
  createXGatewayClient,
  normalizeError,
  resolveConfig,
  XGatewayError,
} from "./lib";

vi.mock("twitter-api-v2", () => {
  type MockTweet = Readonly<{
    id: string;
    text: string;
    author_id: string;
    created_at?: string;
    conversation_id?: string;
    in_reply_to_user_id?: string;
    referenced_tweets?: readonly Readonly<{
      type: "quoted" | "replied_to";
      id: string;
    }>[];
  }>;

  type MockUser = Readonly<{
    id: string;
    username: string;
    name: string;
  }>;

  class ApiResponseError extends Error {
    readonly code: number;
    readonly data: { title?: string; detail?: string };

    constructor(
      message: string,
      options: Readonly<{
        code: number;
        data?: { title?: string; detail?: string };
      }>,
    ) {
      super(message);
      this.code = options.code;
      this.data = options.data ?? {};
    }
  }

  class TwitterV2IncludesHelper {
    readonly result: {
      includes?: {
        tweets?: readonly MockTweet[];
        users?: readonly MockUser[];
      };
    };

    constructor(result: {
      includes?: {
        tweets?: readonly MockTweet[];
        users?: readonly MockUser[];
      };
    }) {
      this.result = result;
    }

    author(tweet: Readonly<{ author_id?: string }>): MockUser | undefined {
      return this.result.includes?.users?.find(
        (user) => user.id === tweet.author_id,
      );
    }

    tweetById(id: string): MockTweet | undefined {
      return this.result.includes?.tweets?.find((tweet) => tweet.id === id);
    }
  }

  class TwitterApi {
    readonly auth: unknown;

    constructor(auth: unknown) {
      this.auth = auth;
    }

    get v1(): {
      verifyCredentials: () => Promise<{
        id_str: string;
        screen_name: string;
        name: string;
      }>;
    } {
      return {
        verifyCredentials: async () => {
          if (
            typeof this.auth === "object" &&
            this.auth !== null &&
            "appKey" in this.auth &&
            this.auth["appKey"] === "bad"
          ) {
            throw new ApiResponseError("Unauthorized", {
              code: 401,
              data: { title: "Unauthorized", detail: "Token expired" },
            });
          }
          return {
            id_str: "oauth1-user",
            screen_name: "oauth1_user",
            name: "OAuth One",
          };
        },
      };
    }

    get readOnly(): TwitterApi {
      return this;
    }

    get readWrite(): TwitterApi {
      return this;
    }

    get v2(): {
      me: () => Promise<{
        data: { id: string; username: string; name: string };
      }>;
      singleTweet: (postId: string) => Promise<{
        data: {
          id: string;
          text: string;
          author_id: string;
          created_at: string;
          conversation_id: string;
          in_reply_to_user_id: string;
          referenced_tweets: readonly [
            { type: "quoted"; id: string },
            { type: "replied_to"; id: string },
          ];
        };
        includes: {
          tweets: readonly [
            {
              id: string;
              text: string;
              author_id: string;
              conversation_id: string;
            },
            {
              id: string;
              text: string;
              author_id: string;
              conversation_id: string;
            },
          ];
          users: readonly [
            { id: string; username: string; name: string },
            { id: string; username: string; name: string },
            { id: string; username: string; name: string },
          ];
        };
      }>;
      userLikedTweets: (
        userId: string,
        options?: { max_results?: number },
      ) => Promise<{
        tweets: readonly MockTweet[];
        includes: TwitterV2IncludesHelper;
        meta: { result_count: number };
      }>;
      tweet: (text: string) => Promise<{ data: { id: string; text: string } }>;
      deleteTweet: (
        postId: string,
      ) => Promise<{ data: { deleted: boolean; postId: string } }>;
      reply: (
        text: string,
        replyToPostId: string,
      ) => Promise<{
        data: { id: string; text: string; replyToPostId: string };
      }>;
      quote: (
        text: string,
        quotedPostId: string,
      ) => Promise<{
        data: { id: string; text: string; quotedPostId: string };
      }>;
      retweet: (
        userId: string,
        postId: string,
      ) => Promise<{
        data: { retweeted: boolean; userId: string; postId: string };
      }>;
      unretweet: (
        userId: string,
        postId: string,
      ) => Promise<{
        data: { retweeted: boolean; userId: string; postId: string };
      }>;
    } {
      return {
        me: async () => {
          if (this.auth === "bad-token") {
            throw new ApiResponseError("Unauthorized", {
              code: 401,
              data: { title: "Unauthorized", detail: "Token expired" },
            });
          }
          return {
            data:
              typeof this.auth === "string"
                ? {
                    id: "bearer-user",
                    username: "bearer_user",
                    name: "Bearer User",
                  }
                : {
                    id: "oauth1-user",
                    username: "oauth1_user",
                    name: "OAuth One",
                  },
          };
        },
        singleTweet: async (postId: string) => {
          if (this.auth === "bad-token") {
            throw new ApiResponseError("Unauthorized", {
              code: 401,
              data: { title: "Unauthorized", detail: "Token expired" },
            });
          }
          return {
            data: {
              id: postId,
              text: `post ${postId}`,
              author_id: "author-1",
              created_at: "2026-03-08T00:00:00.000Z",
              conversation_id: "conversation-1",
              in_reply_to_user_id: "author-2",
              referenced_tweets: [
                { type: "quoted", id: "quoted-1" },
                { type: "replied_to", id: "reply-1" },
              ],
            },
            includes: {
              tweets: [
                {
                  id: "quoted-1",
                  text: "quoted text",
                  author_id: "author-3",
                  conversation_id: "conversation-quoted",
                },
                {
                  id: "reply-1",
                  text: "reply source",
                  author_id: "author-2",
                  conversation_id: "conversation-reply",
                },
              ],
              users: [
                { id: "author-1", username: "author_one", name: "Author One" },
                { id: "author-2", username: "author_two", name: "Author Two" },
                {
                  id: "author-3",
                  username: "author_three",
                  name: "Author Three",
                },
              ],
            },
          };
        },
        userLikedTweets: async (
          userId: string,
          options?: { max_results?: number },
        ) => {
          const count = options?.max_results ?? 2;
          const tweets = [
            {
              id: `${userId}-like-1`,
              text: `liked post 1 for ${userId}`,
              author_id: "author-1",
              created_at: "2026-03-08T01:00:00.000Z",
              conversation_id: "likes-conversation-1",
            },
            {
              id: `${userId}-like-2`,
              text: `liked post 2 for ${userId}`,
              author_id: "author-2",
              created_at: "2026-03-08T02:00:00.000Z",
              conversation_id: "likes-conversation-2",
            },
          ].slice(0, count);
          const includes = {
            users: [
              { id: "author-1", username: "author_one", name: "Author One" },
              { id: "author-2", username: "author_two", name: "Author Two" },
            ],
          };
          return {
            tweets,
            includes: new TwitterV2IncludesHelper({ includes }),
            meta: { result_count: tweets.length },
          };
        },
        tweet: async (text: string) => ({
          data: { id: "tweet-1", text },
        }),
        deleteTweet: async (postId: string) => ({
          data: { deleted: true, postId },
        }),
        reply: async (text: string, replyToPostId: string) => ({
          data: { id: "tweet-2", text, replyToPostId },
        }),
        quote: async (text: string, quotedPostId: string) => ({
          data: { id: "tweet-3", text, quotedPostId },
        }),
        retweet: async (userId: string, postId: string) => ({
          data: { retweeted: true, userId, postId },
        }),
        unretweet: async (userId: string, postId: string) => ({
          data: { retweeted: false, userId, postId },
        }),
      };
    }
  }

  return { ApiResponseError, TwitterApi, TwitterV2IncludesHelper };
});

const ENV_KEYS = [
  "X_GW_CONFIG_MODE",
  "X_GW_TOKEN",
  "X_GW_CONSUMER_KEY",
  "X_GW_CONSUMER_SECRET",
  "X_GW_ACCESS_TOKEN",
  "X_GW_ACCESS_TOKEN_SECRET",
  "X_GW_TIMEOUT_MS",
  "X_GW_RETRY",
  "X_GW_RETRY_BACKOFF",
  "X_GW_RETRY_BASE_MS",
  "X_GW_RETRY_MAX_MS",
  "X_GW_GRAPHQL_BASE_URL",
  "X_GW_AUTH_MODE",
  "X_GW_OUTPUT",
  "X_GW_STRICT_CAPABILITY_CHECKS",
] as const;

const ORIGINAL_FETCH = globalThis.fetch;

afterEach(() => {
  for (const key of ENV_KEYS) {
    delete process.env[key];
  }
  vi.restoreAllMocks();
  globalThis.fetch = ORIGINAL_FETCH;
});

describe("resolveConfig", () => {
  test("uses X_GW_ env vars when parameters are omitted", () => {
    process.env["X_GW_TOKEN"] = "env-token";
    process.env["X_GW_TIMEOUT_MS"] = "45000";
    process.env["X_GW_RETRY"] = "3";
    process.env["X_GW_RETRY_BACKOFF"] = "fixed";
    process.env["X_GW_RETRY_BASE_MS"] = "200";
    process.env["X_GW_RETRY_MAX_MS"] = "5000";
    process.env["X_GW_GRAPHQL_BASE_URL"] = "https://example.com/graphql";

    const resolved = resolveConfig();

    expect(resolved.auth.token).toBe("env-token");
    expect(resolved.graphqlBaseUrl).toBe("https://example.com/graphql");
    expect(resolved.timeoutMs).toBe(45000);
    expect(resolved.retry.retries).toBe(3);
    expect(resolved.retry.backoff).toBe("fixed");
    expect(resolved.retry.baseDelayMs).toBe(200);
    expect(resolved.retry.maxDelayMs).toBe(5000);
  });

  test("prefers explicit parameters over env", () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const resolved = resolveConfig({
      auth: { token: "param-token" },
      graphqlBaseUrl: "https://override.example/graphql",
      retry: {
        retries: 5,
        backoff: "none",
        baseDelayMs: 1,
        maxDelayMs: 2,
      },
    });

    expect(resolved.auth.token).toBe("param-token");
    expect(resolved.graphqlBaseUrl).toBe("https://override.example/graphql");
    expect(resolved.retry.retries).toBe(5);
    expect(resolved.retry.backoff).toBe("none");
    expect(resolved.retry.baseDelayMs).toBe(1);
    expect(resolved.retry.maxDelayMs).toBe(2);
  });

  test("authMode env ignores auth parameters", () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const resolved = resolveConfig({
      configMode: "env",
      auth: { token: "param-token" },
    });

    expect(resolved.auth.token).toBe("env-token");
  });

  test("authMode params ignores env auth", () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const resolved = resolveConfig({
      configMode: "params",
      auth: { token: "param-token" },
    });

    expect(resolved.auth.token).toBe("param-token");
  });

  test("uses X_GW_CONFIG_MODE when present", () => {
    process.env["X_GW_CONFIG_MODE"] = "env";
    process.env["X_GW_TOKEN"] = "env-token";

    const resolved = resolveConfig({
      auth: { token: "param-token" },
    });

    expect(resolved.auth.token).toBe("env-token");
    expect(resolved.configMode).toBe("env");
  });

  test("tolerates legacy X_GW_AUTH_MODE auth-type values without treating them as config mode", () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const resolved = resolveConfig();
    const client = createXGatewayClient();

    expect(resolved.configMode).toBe("mixed");
    expect(client.getResolvedConfig().configMode).toBe("mixed");
  });

  test("accepts zero retries from env", () => {
    process.env["X_GW_RETRY"] = "0";

    const resolved = resolveConfig();

    expect(resolved.retry.retries).toBe(0);
  });

  test("rejects malformed retry env values instead of truncating or falling back", () => {
    process.env["X_GW_RETRY"] = "1.5";

    expect(() => resolveConfig()).toThrowError(XGatewayError);
  });

  test("rejects invalid auth-mode env values instead of silently falling back", () => {
    process.env["X_GW_AUTH_MODE"] = "broken";

    expect(() => resolveConfig()).toThrowError(XGatewayError);
  });

  test("does not accept the removed X_GW_API_BASE_URL compatibility env", () => {
    process.env["X_GW_API_BASE_URL"] = "https://legacy.example/graphql";

    const resolved = resolveConfig();

    expect(resolved.graphqlBaseUrl).toBeUndefined();
  });
});

describe("computeBackoffDelayMs", () => {
  test("returns fixed delay for fixed strategy", () => {
    const delay = computeBackoffDelayMs(2, "fixed", 300, 1000, 0.5);
    expect(delay).toBe(300);
  });

  test("returns zero for none strategy", () => {
    const delay = computeBackoffDelayMs(5, "none", 300, 1000, 0.5);
    expect(delay).toBe(0);
  });

  test("caps exponential-jitter delay by max", () => {
    const delay = computeBackoffDelayMs(
      8,
      "exponential-jitter",
      300,
      1000,
      0.99,
    );
    expect(delay).toBeLessThanOrEqual(1000);
  });
});

describe("normalizeError", () => {
  test("maps network-ish error messages to NETWORK_FAILURE", () => {
    const error = normalizeError(
      new Error("fetch failed: timeout while connecting"),
    );

    expect(error).toBeInstanceOf(XGatewayError);
    expect(error.payload.code).toBe("NETWORK_FAILURE");
    expect(error.payload.retryable).toBe(true);
  });

  test("returns INTERNAL_ERROR for unknown thrown values", () => {
    const error = normalizeError("unexpected");

    expect(error.payload.code).toBe("INTERNAL_ERROR");
  });
});

describe("createXGatewayClient", () => {
  test("allows capability inspection without configured auth", () => {
    const client = createXGatewayClient();

    expect(client.capabilitiesGet("graphql.request")).toMatchObject({
      id: "graphql.request",
      status: "implemented",
    });
  });

  test("reports auth readiness without throwing when auth is missing", async () => {
    const client = createXGatewayClient();

    await expect(client.authVerify()).resolves.toMatchObject({
      ready: false,
      authMode: "unconfigured",
      transport: "hybrid",
      capabilities: expect.arrayContaining([
        expect.objectContaining({
          capabilityId: "graphql.request",
          status: "blocked",
          requirement: "bearer",
        }),
        expect.objectContaining({
          capabilityId: "post.create",
          status: "blocked",
          requirement: "oauth1",
        }),
      ]),
    });
  });

  test("reports OAuth1 readiness for REST compatibility commands", async () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(client.authVerify()).resolves.toMatchObject({
      ready: true,
      authMode: "oauth1",
      transport: "hybrid",
      capabilities: expect.arrayContaining([
        expect.objectContaining({
          capabilityId: "account.me",
          status: "ready",
          selectedAuthMode: "oauth1",
        }),
        expect.objectContaining({
          capabilityId: "graphql.request",
          status: "blocked",
          requirement: "bearer",
        }),
        expect.objectContaining({
          capabilityId: "post.repost",
          status: "ready",
          selectedAuthMode: "oauth1",
        }),
      ]),
    });
  });

  test("reports conditional bearer readiness for account identity lookup", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(client.authVerify()).resolves.toMatchObject({
      ready: true,
      authMode: "bearer",
      transport: "hybrid",
      capabilities: expect.arrayContaining([
        expect.objectContaining({
          capabilityId: "graphql.request",
          status: "ready",
          selectedAuthMode: "bearer",
        }),
        expect.objectContaining({
          capabilityId: "account.me",
          status: "conditional",
          requirement: "user-context-bearer",
          selectedAuthMode: "bearer",
        }),
        expect.objectContaining({
          capabilityId: "post.get",
          status: "ready",
          selectedAuthMode: "bearer",
        }),
        expect.objectContaining({
          capabilityId: "likes.list",
          status: "ready",
          selectedAuthMode: "bearer",
        }),
        expect.objectContaining({
          capabilityId: "post.create",
          status: "blocked",
          requirement: "oauth1",
        }),
      ]),
    });
  });

  test("reports both available auth families in mixed-auth environments", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(client.authVerify()).resolves.toMatchObject({
      ready: true,
      authMode: "bearer",
      availableAuthModes: ["oauth1", "bearer"],
      transport: "hybrid",
      capabilities: expect.arrayContaining([
        expect.objectContaining({
          capabilityId: "graphql.request",
          status: "ready",
          selectedAuthMode: "bearer",
        }),
        expect.objectContaining({
          capabilityId: "account.me",
          status: "ready",
          selectedAuthMode: "oauth1",
        }),
        expect.objectContaining({
          capabilityId: "post.get",
          status: "ready",
          selectedAuthMode: "oauth1",
        }),
        expect.objectContaining({
          capabilityId: "post.create",
          status: "ready",
          selectedAuthMode: "oauth1",
        }),
      ]),
    });
  });

  test("sends raw GraphQL requests through fetch", async () => {
    process.env["X_GW_TOKEN"] = "env-token";
    process.env["X_GW_GRAPHQL_BASE_URL"] = "https://example.com/graphql";

    const fetchMock = vi.fn(async () => {
      return new Response(JSON.stringify({ data: { viewer: { id: "1" } } }), {
        status: 200,
        headers: {
          "content-type": "application/json",
        },
      });
    });
    globalThis.fetch = fetchMock as typeof fetch;

    const client = createXGatewayClient();
    const result = await client.request<{ data: { viewer: { id: string } } }>({
      operationName: "Viewer",
      documentId: "doc-1",
      variables: { withSafetyModeUserFields: true },
    });

    expect(result.data.viewer.id).toBe("1");
    expect(fetchMock).toHaveBeenCalledWith(
      "https://example.com/graphql/doc-1/Viewer",
      expect.objectContaining({
        method: "POST",
      }),
    );
  });

  test("accepts GraphQL JSON media types with +json suffix", async () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const fetchMock = vi.fn(async () => {
      return new Response(JSON.stringify({ data: { viewer: { id: "2" } } }), {
        status: 200,
        headers: {
          "content-type": "application/graphql-response+json; charset=utf-8",
        },
      });
    });
    globalThis.fetch = fetchMock as typeof fetch;

    const client = createXGatewayClient();
    const result = await client.request<{ data: { viewer: { id: string } } }>({
      operationName: "Viewer",
      documentId: "doc-2",
    });

    expect(result.data.viewer.id).toBe("2");
  });

  test("rejects GraphQL requests when only OAuth1 credentials are configured", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.request({
        operationName: "Viewer",
        documentId: "doc-1",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
  });

  test("rejects GraphQL requests without documentId or query", async () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const client = createXGatewayClient();

    await expect(
      client.request({
        operationName: "Viewer",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
      }),
    });
  });

  test("rejects GraphQL requests when both documentId and query are provided", async () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const client = createXGatewayClient();

    await expect(
      client.request({
        operationName: "Viewer",
        documentId: "doc-1",
        query: "query Viewer { viewer { id } }",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
      }),
    });
  });

  test("includes retry exhaustion context and retry-after metadata for retryable failures", async () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const fetchMock = vi.fn(async () => {
      return new Response(JSON.stringify({ error: "rate limited" }), {
        status: 429,
        headers: {
          "content-type": "application/json",
          "retry-after": "0",
        },
      });
    });
    globalThis.fetch = fetchMock as typeof fetch;

    const client = createXGatewayClient({
      retry: {
        retries: 1,
        backoff: "fixed",
        baseDelayMs: 999,
        maxDelayMs: 999,
      },
      timeoutMs: 5_000,
    });

    await expect(
      client.request({
        operationName: "Viewer",
        documentId: "doc-1",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "RATE_LIMITED",
        attempts: 2,
        retryAfterMs: 0,
        details: expect.stringContaining("Retry policy exhausted"),
      }),
    });
  });

  test("exposes the stable SDK surface with capability adapters and raw GraphQL", () => {
    const client = createXGatewayClient();

    expect("request" in client).toBe(true);
    expect("apiRequest" in client).toBe(true);
    expect("capabilitiesList" in client).toBe(true);
    expect("accountMe" in client).toBe(true);
    expect("postGet" in client).toBe(true);
    expect("likesList" in client).toBe(true);
    expect("postCreate" in client).toBe(true);
    expect("postDelete" in client).toBe(true);
    expect("postReply" in client).toBe(true);
    expect("postQuote" in client).toBe(true);
    expect("postRepost" in client).toBe(true);
    expect("postUndoRepost" in client).toBe(true);
  });

  test("supports accountMe through the REST compatibility adapter", async () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(client.accountMe()).resolves.toMatchObject({
      id: "oauth1-user",
      username: "oauth1_user",
    });
  });

  test("supports accountMe with bearer auth through the REST compatibility adapter", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(client.accountMe()).resolves.toMatchObject({
      id: "bearer-user",
      username: "bearer_user",
    });
  });

  test("supports postGet through the REST compatibility adapter", async () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(client.postGet({ postId: "post-1" })).resolves.toMatchObject({
      post: {
        id: "post-1",
        text: "post post-1",
        author: {
          username: "author_one",
        },
      },
      referencedPosts: [
        {
          relation: "quoted",
          id: "quoted-1",
          author: {
            username: "author_three",
          },
        },
        {
          relation: "replied_to",
          id: "reply-1",
          author: {
            username: "author_two",
          },
        },
      ],
    });
  });

  test("supports postGet with bearer auth through the REST compatibility adapter", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(client.postGet({ postId: "post-2" })).resolves.toMatchObject({
      post: {
        id: "post-2",
      },
      referencedPosts: expect.arrayContaining([
        expect.objectContaining({ relation: "quoted", id: "quoted-1" }),
      ]),
    });
  });

  test("supports likesList through the REST compatibility adapter", async () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.likesList({ userId: "user-1", limit: 1 }),
    ).resolves.toEqual({
      userId: "user-1",
      posts: [
        {
          id: "user-1-like-1",
          text: "liked post 1 for user-1",
          createdAt: "2026-03-08T01:00:00.000Z",
          conversationId: "likes-conversation-1",
          author: {
            id: "author-1",
            username: "author_one",
            name: "Author One",
          },
        },
      ],
    });
  });

  test("supports likesList with bearer auth through the REST compatibility adapter", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(client.likesList({ userId: "user-2" })).resolves.toMatchObject(
      {
        userId: "user-2",
        posts: [
          expect.objectContaining({
            id: "user-2-like-1",
            author: expect.objectContaining({
              username: "author_one",
            }),
          }),
          expect.objectContaining({
            id: "user-2-like-2",
          }),
        ],
      },
    );
  });

  test("prefers reviewed OAuth1 read routes over a broken bearer token in mixed-auth mode", async () => {
    process.env["X_GW_TOKEN"] = "bad-token";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.postGet({ postId: "post-mixed" }),
    ).resolves.toMatchObject({
      post: {
        id: "post-mixed",
      },
    });

    await expect(
      client.likesList({ userId: "user-mixed" }),
    ).resolves.toMatchObject({
      userId: "user-mixed",
      posts: expect.arrayContaining([
        expect.objectContaining({
          id: "user-mixed-like-1",
        }),
      ]),
    });
  });

  test("supports postCreate through the REST compatibility adapter", async () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(client.postCreate({ text: "hello" })).resolves.toMatchObject({
      data: {
        id: "tweet-1",
        text: "hello",
      },
    });
  });

  test("supports postDelete through the REST compatibility adapter", async () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.postDelete({ postId: "tweet-9" }),
    ).resolves.toMatchObject({
      data: {
        deleted: true,
        postId: "tweet-9",
      },
    });
  });

  test("supports postReply through the REST compatibility adapter", async () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.postReply({ text: "hello", replyToPostId: "post-1" }),
    ).resolves.toMatchObject({
      data: {
        id: "tweet-2",
        text: "hello",
        replyToPostId: "post-1",
      },
    });
  });

  test("supports postQuote through the REST compatibility adapter", async () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.postQuote({ text: "hello", quotedPostId: "post-2" }),
    ).resolves.toMatchObject({
      data: {
        id: "tweet-3",
        text: "hello",
        quotedPostId: "post-2",
      },
    });
  });

  test("supports postRepost and postUndoRepost through the REST compatibility adapter", async () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.postRepost({ postId: "post-3" }),
    ).resolves.toMatchObject({
      data: {
        retweeted: true,
        userId: "oauth1-user",
        postId: "post-3",
      },
    });
    await expect(
      client.postUndoRepost({ postId: "post-3" }),
    ).resolves.toMatchObject({
      data: {
        retweeted: false,
        userId: "oauth1-user",
        postId: "post-3",
      },
    });
  });

  test("prefers OAuth1 for stable posting when bearer and OAuth1 credentials are both present", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(client.postCreate({ text: "hello" })).resolves.toMatchObject({
      data: {
        id: "tweet-1",
        text: "hello",
      },
    });
    await expect(
      client.postRepost({ postId: "post-3" }),
    ).resolves.toMatchObject({
      data: {
        retweeted: true,
        userId: "oauth1-user",
        postId: "post-3",
      },
    });
  });

  test("rejects bearer auth for stable postCreate until a reviewed user-context path exists", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(client.postCreate({ text: "hello" })).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
        details: expect.stringContaining("OAuth1 credentials only"),
      }),
    });
  });

  test("rejects bearer auth for expanded stable posting helpers", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(
      client.postDelete({ postId: "tweet-9" }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
        details: expect.stringContaining("OAuth1 credentials only"),
      }),
    });
    await expect(
      client.postReply({ text: "hello", replyToPostId: "post-1" }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
        details: expect.stringContaining("OAuth1 credentials only"),
      }),
    });
    await expect(
      client.postQuote({ text: "hello", quotedPostId: "post-2" }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
        details: expect.stringContaining("OAuth1 credentials only"),
      }),
    });
    await expect(client.postRepost({ postId: "post-3" })).rejects.toMatchObject(
      {
        payload: expect.objectContaining({
          code: "UNSUPPORTED",
          details: expect.stringContaining("OAuth1 credentials only"),
        }),
      },
    );
  });

  test("normalizes adapter auth errors for SDK callers", async () => {
    process.env["X_GW_TOKEN"] = "bad-token";

    const client = createXGatewayClient();

    await expect(client.accountMe()).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "AUTH_EXPIRED",
        classification: "auth",
        summary: "Authenticated account lookup failed",
        details: expect.stringContaining("rest-v2/bearer"),
        remediations: expect.arrayContaining([
          "Refresh or replace the configured credential, then retry the same capability.",
        ]),
      }),
    });
  });

  test("supports the project-owned GraphQL accountMe contract through the SDK", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: "query { accountMe { id username } }",
      }),
    ).resolves.toEqual({
      data: {
        accountMe: {
          id: "oauth1-user",
          username: "oauth1_user",
        },
      },
    });
  });

  test("supports the project-owned GraphQL post contract through the SDK", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query:
          'query { post(id: "post-42") { id text author { username } referencedPosts { relation id } } }',
      }),
    ).resolves.toEqual({
      data: {
        post: {
          id: "post-42",
          text: "post post-42",
          author: {
            username: "author_one",
          },
          referencedPosts: [
            {
              relation: "quoted",
              id: "quoted-1",
            },
            {
              relation: "replied_to",
              id: "reply-1",
            },
          ],
        },
      },
    });
  });

  test("supports the project-owned GraphQL mutation contract through the SDK", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: 'mutation { createPost(text: "hello") { id text } }',
      }),
    ).resolves.toEqual({
      data: {
        createPost: {
          id: "tweet-1",
          text: "hello",
        },
      },
    });
  });

  test("keeps public GraphQL capability routing auth-specific in mixed-auth mode", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: "query { accountMe { id username } }",
      }),
    ).resolves.toEqual({
      data: {
        accountMe: {
          id: "oauth1-user",
          username: "oauth1_user",
        },
      },
    });

    await expect(
      client.apiRequest({
        query: 'mutation { createPost(text: "hello") { id text } }',
      }),
    ).resolves.toEqual({
      data: {
        createPost: {
          id: "tweet-1",
          text: "hello",
        },
      },
    });
  });

  test("supports the project-owned GraphQL likedPosts contract through the SDK", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: 'query { likedPosts(userId: "user-1", limit: 20) { id } }',
      }),
    ).resolves.toEqual({
      data: {
        likedPosts: [{ id: "user-1-like-1" }, { id: "user-1-like-2" }],
      },
    });
  });

  test("rejects raw X-shaped fields on the project-owned GraphQL contract", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: "query { UserByScreenName { id } }",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL field 'UserByScreenName' is not part of the stable x-gateway contract.",
        ),
      }),
    });
  });
});

describe("executeCli", () => {
  test("rejects deferred legacy command groups at the CLI boundary", async () => {
    await expect(
      executeCli(["tweet", "get", "--tweet-id", "1"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
  });

  test("rejects unknown command groups as validation errors", async () => {
    await expect(
      executeCli(["twet", "get", "--tweet-id", "1"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
      }),
    });
  });

  test("rejects invalid auth-mode values", async () => {
    await expect(
      executeCli(["capabilities", "list", "--auth-mode", "broken"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
      }),
    });
  });

  test("rejects malformed numeric flags instead of truncating them", async () => {
    await expect(
      executeCli(["capabilities", "list", "--retry", "1.5"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
      }),
    });
  });

  test("rejects bare required string flags instead of treating them as true", async () => {
    await expect(
      executeCli(
        ["graphql", "request", "--operation-name", "--document-id", "doc-1"],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Flag --operation-name requires a value",
        ),
      }),
    });
  });

  test("rejects bare numeric flags instead of coercing them to true", async () => {
    await expect(
      executeCli(
        [
          "graphql",
          "request",
          "--operation-name",
          "Viewer",
          "--document-id",
          "doc-1",
          "--retry",
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("Flag --retry requires a value"),
      }),
    });
  });

  test("rejects mutation GraphQL requests in reader mode", async () => {
    await expect(
      executeCli(
        [
          "graphql",
          "request",
          "--operation-type",
          "mutation",
          "--operation-name",
          "CreatePost",
          "--document-id",
          "doc-1",
        ],
        {
          commandName: "x-gateway-reader",
          surface: "reader",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
  });

  test("honors X_GW_CONFIG_MODE from env when CLI flags omit config-mode", async () => {
    process.env["X_GW_CONFIG_MODE"] = "params";
    process.env["X_GW_TOKEN"] = "env-token";

    await expect(
      executeCli(
        [
          "graphql",
          "request",
          "--operation-name",
          "Viewer",
          "--document-id",
          "doc-1",
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "AUTH_MISSING",
      }),
    });
  });

  test("accepts config-mode as the preferred CLI flag", async () => {
    await expect(
      executeCli(["capabilities", "list", "--config-mode", "broken"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("Flag --config-mode must be one of"),
      }),
    });
  });

  test("rejects conflicting config-mode and auth-mode aliases", async () => {
    await expect(
      executeCli(
        [
          "capabilities",
          "list",
          "--config-mode",
          "env",
          "--auth-mode",
          "params",
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("must match when both are provided"),
      }),
    });
  });

  test("does not fail when legacy X_GW_AUTH_MODE is set to oauth1 in the shell", async () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    await expect(
      executeCli(["auth", "verify"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).resolves.toMatchObject({
      ready: true,
      authMode: "oauth1",
      transport: "hybrid",
    });
  });

  test("supports account me through the CLI", async () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    await expect(
      executeCli(["account", "me"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).resolves.toMatchObject({
      id: "oauth1-user",
      username: "oauth1_user",
    });
  });

  test("supports the project-owned GraphQL contract through the CLI", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    await expect(
      executeCli(
        ["api", "request", "--query", "query { accountMe { id username } }"],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).resolves.toEqual({
      data: {
        accountMe: {
          id: "oauth1-user",
          username: "oauth1_user",
        },
      },
    });
  });

  test("keeps api request mutations blocked in reader mode", async () => {
    await expect(
      executeCli(
        [
          "api",
          "request",
          "--query",
          'mutation { createPost(text: "hello") { id } }',
        ],
        {
          commandName: "x-gateway-reader",
          surface: "reader",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
  });

  test("supports post get through the CLI on both surfaces", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    await expect(
      executeCli(["post", "get", "--post-id", "post-7"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).resolves.toMatchObject({
      post: {
        id: "post-7",
      },
    });

    await expect(
      executeCli(["post", "get", "--post-id", "post-8"], {
        commandName: "x-gateway-reader",
        surface: "reader",
      }),
    ).resolves.toMatchObject({
      post: {
        id: "post-8",
      },
    });
  });

  test("supports likes list through the CLI on both surfaces", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    await expect(
      executeCli(["likes", "list", "--user-id", "user-7", "--limit", "1"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).resolves.toEqual({
      userId: "user-7",
      posts: [
        {
          id: "user-7-like-1",
          text: "liked post 1 for user-7",
          createdAt: "2026-03-08T01:00:00.000Z",
          conversationId: "likes-conversation-1",
          author: {
            id: "author-1",
            username: "author_one",
            name: "Author One",
          },
        },
      ],
    });

    await expect(
      executeCli(["likes", "list", "--user-id", "user-8"], {
        commandName: "x-gateway-reader",
        surface: "reader",
      }),
    ).resolves.toMatchObject({
      userId: "user-8",
      posts: expect.arrayContaining([
        expect.objectContaining({
          id: "user-8-like-1",
        }),
      ]),
    });
  });

  test("omits write commands from reader usage output", async () => {
    await expect(
      executeCli([], {
        commandName: "x-gateway-reader",
        surface: "reader",
      }),
    ).resolves.toContain("post get");
    await expect(
      executeCli([], {
        commandName: "x-gateway-reader",
        surface: "reader",
      }),
    ).resolves.not.toContain("post create");
  });

  test("supports post create through the full CLI", async () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    await expect(
      executeCli(["post", "create", "--text", "hello"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).resolves.toMatchObject({
      data: {
        id: "tweet-1",
        text: "hello",
      },
    });
  });

  test("supports post delete through the full CLI", async () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    await expect(
      executeCli(["post", "delete", "--post-id", "tweet-9"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).resolves.toMatchObject({
      data: {
        deleted: true,
        postId: "tweet-9",
      },
    });
  });

  test("supports expanded post commands through the full CLI", async () => {
    process.env["X_GW_AUTH_MODE"] = "oauth1";
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    await expect(
      executeCli(
        ["post", "reply", "--text", "hello", "--reply-to-post-id", "post-1"],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).resolves.toMatchObject({
      data: {
        id: "tweet-2",
        replyToPostId: "post-1",
      },
    });
    await expect(
      executeCli(
        ["post", "quote", "--text", "hello", "--quoted-post-id", "post-2"],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).resolves.toMatchObject({
      data: {
        id: "tweet-3",
        quotedPostId: "post-2",
      },
    });
    await expect(
      executeCli(["post", "repost", "--post-id", "post-3"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).resolves.toMatchObject({
      data: {
        retweeted: true,
        postId: "post-3",
      },
    });
    await expect(
      executeCli(["post", "unrepost", "--post-id", "post-3"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).resolves.toMatchObject({
      data: {
        retweeted: false,
        postId: "post-3",
      },
    });
  });

  test("rejects post create with bearer auth through the CLI", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    await expect(
      executeCli(["post", "create", "--text", "hello"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
        details: expect.stringContaining("OAuth1 credentials only"),
      }),
    });
  });

  test("rejects expanded post commands with bearer auth through the CLI", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    await expect(
      executeCli(["post", "delete", "--post-id", "tweet-9"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
    await expect(
      executeCli(
        ["post", "reply", "--text", "hello", "--reply-to-post-id", "post-1"],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
    await expect(
      executeCli(
        ["post", "quote", "--text", "hello", "--quoted-post-id", "post-2"],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
    await expect(
      executeCli(["post", "repost", "--post-id", "post-3"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
  });

  test("keeps post create blocked in reader mode", async () => {
    await expect(
      executeCli(["post", "create", "--text", "hello"], {
        commandName: "x-gateway-reader",
        surface: "reader",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
    await expect(
      executeCli(["post", "delete", "--post-id", "tweet-9"], {
        commandName: "x-gateway-reader",
        surface: "reader",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
  });

  test("includes transport strategy and tightened auth metadata in capability inventory", () => {
    const client = createXGatewayClient();
    const capability = client.capabilitiesGet("post.delete");
    const deferredRead = client.capabilitiesGet("timeline.search");
    const deferredSocial = client.capabilitiesGet("social.follows");
    const stableLikes = client.capabilitiesGet("likes.list");
    const rawGraphql = client.capabilitiesGet("graphql.request");

    expect(capability.transportStrategy).toBe("rest-v2");
    expect(capability.publicOperationName).toBe("deletePost");
    expect(capability.surfaceCategory).toBe("stable-contract");
    expect(capability.accessType).toBe("write");
    expect(capability.preferredTransport).toBe("rest-v2");
    expect(capability.authModes).toEqual(["oauth1"]);
    expect(stableLikes.status).toBe("implemented");
    expect(stableLikes.publicOperationName).toBe("likedPosts");
    expect(stableLikes.surfaceCategory).toBe("stable-contract");
    expect(stableLikes.transportStrategy).toBe("rest-v2");
    expect(stableLikes.authModes).toEqual(["oauth1", "bearer"]);
    expect(rawGraphql.surfaceCategory).toBe("escape-hatch");
    expect(deferredRead.notes).not.toContain(
      "GraphQL-only transport is enforced",
    );
    expect(deferredRead.surfaceCategory).toBe("deferred");
    expect(deferredSocial.notes).not.toContain(
      "GraphQL-only transport is enforced",
    );
    expect(deferredSocial.surfaceCategory).toBe("deferred");
  });

  test("keeps public GraphQL field names aligned with stable capability metadata", () => {
    const client = createXGatewayClient();
    const publicOperationNames = client
      .capabilitiesList()
      .filter(
        (capability) =>
          capability.status === "implemented" &&
          typeof capability.publicOperationName === "string",
      )
      .map((capability) => capability.publicOperationName)
      .sort();

    expect(publicOperationNames).toEqual([
      "accountMe",
      "createPost",
      "deletePost",
      "likedPosts",
      "post",
      "quotePost",
      "replyToPost",
      "repostPost",
      "unrepostPost",
    ]);
  });

  test("keeps implemented stable capabilities aligned across metadata, planning, and execution", () => {
    const client = createXGatewayClient();
    const implementedStableCapabilityIds = client
      .capabilitiesList()
      .filter(
        (capability) =>
          capability.status === "implemented" &&
          STABLE_CAPABILITY_IDS.includes(
            capability.id as (typeof STABLE_CAPABILITY_IDS)[number],
          ),
      )
      .map((capability) => capability.id)
      .sort();

    expect(implementedStableCapabilityIds).toEqual(
      [...STABLE_CAPABILITY_IDS].sort(),
    );
  });

  test("honors retry env settings when CLI flags omit retry controls", async () => {
    process.env["X_GW_TOKEN"] = "env-token";
    process.env["X_GW_RETRY"] = "1";

    const fetchMock = vi.fn(async () => {
      return new Response(JSON.stringify({ error: "rate limited" }), {
        status: 429,
        headers: {
          "content-type": "application/json",
          "retry-after": "0",
        },
      });
    });
    globalThis.fetch = fetchMock as typeof fetch;

    await expect(
      executeCli(
        [
          "graphql",
          "request",
          "--operation-name",
          "Viewer",
          "--document-id",
          "doc-1",
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "RATE_LIMITED",
        attempts: 2,
      }),
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  test("accepts --graphql-base-url as the GraphQL-only endpoint override", async () => {
    process.env["X_GW_TOKEN"] = "env-token";

    const fetchMock = vi.fn(async () => {
      return new Response(JSON.stringify({ data: { viewer: { id: "1" } } }), {
        status: 200,
        headers: {
          "content-type": "application/json",
        },
      });
    });
    globalThis.fetch = fetchMock as typeof fetch;

    await expect(
      executeCli(
        [
          "graphql",
          "request",
          "--operation-name",
          "Viewer",
          "--document-id",
          "doc-1",
          "--graphql-base-url",
          "https://cli.example/graphql",
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).resolves.toMatchObject({
      data: {
        viewer: {
          id: "1",
        },
      },
    });

    expect(fetchMock).toHaveBeenCalledWith(
      "https://cli.example/graphql/doc-1/Viewer",
      expect.any(Object),
    );
  });

  test("validates bare global trace-id flags through the normal CLI error path", async () => {
    await expect(
      executeCli(["health", "--trace-id"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("Flag --trace-id requires a value"),
      }),
    });
  });

  test("rejects deprecated api-base flag aliases instead of silently accepting them", async () => {
    await expect(
      executeCli(
        [
          "graphql",
          "request",
          "--operation-name",
          "Viewer",
          "--document-id",
          "doc-1",
          "--api-base-url",
          "https://legacy.example/graphql",
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Flag --api-base-url is no longer supported",
        ),
      }),
    });
  });

  test("validates global retry flags even for local-only commands", async () => {
    await expect(
      executeCli(["health", "--retry", "1.5"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("Flag --retry must be an integer"),
      }),
    });
  });

  test("rejects unknown flags instead of ignoring them", async () => {
    await expect(
      executeCli(["health", "--mystery-flag", "1"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("Unknown flag --mystery-flag"),
      }),
    });
  });
});
