import { printSchema } from "graphql";
import { afterEach, describe, expect, test, vi } from "vitest";
import { executeCli } from "./cli";
import { STABLE_CAPABILITY_IDS } from "./capability-metadata";
import {
  createPublicApiRequestPlan,
  projectPublicSelection,
} from "./public-api-contract";
import { parsePublicGraphqlDocument } from "./public-graphql-parser";
import { PUBLIC_GRAPHQL_SCHEMA } from "./public-graphql-schema";
import {
  computeBackoffDelayMs,
  createXGatewayClient,
  normalizeError,
  resolveConfig,
  XGatewayError,
} from "./lib";

const twitterMockState = {
  uploadedMedia: [] as Array<Readonly<{ filePath: string; target?: string }>>,
  mediaMetadata: [] as Array<
    Readonly<{ mediaId: string; altText?: string | undefined }>
  >,
  tweetCalls: [] as Array<
    Readonly<{
      text: string;
      mediaIds: readonly string[];
      kind: "tweet" | "reply" | "quote";
    }>
  >,
  timelineCalls: [] as Array<
    Readonly<{
      kind: "search" | "home" | "user" | "mentions";
      authMode: "oauth1" | "bearer";
      query?: string;
      userId?: string;
      maxResults?: number;
      paginationToken?: string;
    }>
  >,
};

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

  type MockTimelinePayload = Readonly<{
    data: readonly MockTweet[];
    includes: {
      users: readonly MockUser[];
    };
    meta: {
      result_count: number;
      next_token?: string;
      previous_token?: string;
      newest_id: string;
      oldest_id: string;
    };
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
      uploadMedia: (
        filePath: string,
        options?: { target?: string },
      ) => Promise<string>;
      createMediaMetadata: (
        mediaId: string,
        metadata: { alt_text?: { text: string } },
      ) => Promise<void>;
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
        uploadMedia: async (
          filePath: string,
          options?: { target?: string },
        ) => {
          const mediaId = `media-${twitterMockState.uploadedMedia.length + 1}`;
          twitterMockState.uploadedMedia.push({
            filePath,
            ...(options?.target === undefined
              ? {}
              : { target: options.target }),
          });
          return mediaId;
        },
        createMediaMetadata: async (
          mediaId: string,
          metadata: { alt_text?: { text: string } },
        ) => {
          twitterMockState.mediaMetadata.push({
            mediaId,
            ...(metadata.alt_text?.text === undefined
              ? {}
              : { altText: metadata.alt_text.text }),
          });
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
      search: (
        query: string,
        options?: { max_results?: number; next_token?: string },
      ) => Promise<{ data: MockTimelinePayload }>;
      homeTimeline: (options?: {
        max_results?: number;
        pagination_token?: string;
      }) => Promise<{ data: MockTimelinePayload }>;
      userTimeline: (
        userId: string,
        options?: { max_results?: number; pagination_token?: string },
      ) => Promise<{ data: MockTimelinePayload }>;
      userMentionTimeline: (
        userId: string,
        options?: { max_results?: number; pagination_token?: string },
      ) => Promise<{ data: MockTimelinePayload }>;
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
      tweet: (
        text: string,
        payload?: { media?: { media_ids?: readonly string[] } },
      ) => Promise<{
        data: {
          id: string;
          text: string;
          mediaIds?: readonly string[];
        };
      }>;
      deleteTweet: (
        postId: string,
      ) => Promise<{ data: { deleted: boolean; postId: string } }>;
      reply: (
        text: string,
        replyToPostId: string,
        payload?: { media?: { media_ids?: readonly string[] } },
      ) => Promise<{
        data: {
          id: string;
          text: string;
          replyToPostId: string;
          mediaIds?: readonly string[];
        };
      }>;
      quote: (
        text: string,
        quotedPostId: string,
        payload?: { media?: { media_ids?: readonly string[] } },
      ) => Promise<{
        data: {
          id: string;
          text: string;
          quotedPostId: string;
          mediaIds?: readonly string[];
        };
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
      const buildTimelinePayload = (
        prefix: string,
        count: number,
        page: 1 | 2,
      ): MockTimelinePayload => {
        const base = page === 1 ? 1 : count + 1;
        const tweets = Array.from({ length: count }, (_, index) => {
          const ordinal = base + index;
          return {
            id: `${prefix}-${ordinal}`,
            text: `${prefix} post ${ordinal}`,
            author_id: ordinal % 2 === 0 ? "author-2" : "author-1",
            created_at: `2026-03-08T0${(ordinal % 4) + 1}:00:00.000Z`,
            conversation_id: `${prefix}-conversation-${ordinal}`,
          };
        });
        return {
          data: tweets,
          includes: {
            users: [
              { id: "author-1", username: "author_one", name: "Author One" },
              { id: "author-2", username: "author_two", name: "Author Two" },
            ],
          },
          meta: {
            result_count: tweets.length,
            ...(page === 1 ? { next_token: "page-2" } : {}),
            ...(page === 2 ? { previous_token: "page-1" } : {}),
            newest_id: tweets[0]?.id ?? `${prefix}-missing`,
            oldest_id:
              tweets[tweets.length - 1]?.id ?? `${prefix}-missing-oldest`,
          },
        };
      };
      const authMode =
        typeof this.auth === "string"
          ? ("bearer" as const)
          : ("oauth1" as const);
      return {
        search: async (
          query: string,
          options?: { max_results?: number; next_token?: string },
        ) => {
          if (this.auth === "bad-token") {
            throw new ApiResponseError("Unauthorized", {
              code: 401,
              data: { title: "Unauthorized", detail: "Token expired" },
            });
          }
          twitterMockState.timelineCalls.push({
            kind: "search",
            authMode,
            query,
            ...(options?.max_results === undefined
              ? {}
              : { maxResults: options.max_results }),
            ...(options?.next_token === undefined
              ? {}
              : { paginationToken: options.next_token }),
          });
          const count = options?.max_results ?? 10;
          const page = options?.next_token === "page-2" ? 2 : 1;
          return {
            data: buildTimelinePayload(`search-${query}`, count, page),
          };
        },
        homeTimeline: async (options?: {
          max_results?: number;
          pagination_token?: string;
        }) => {
          if (this.auth === "bad-token") {
            throw new ApiResponseError("Unauthorized", {
              code: 401,
              data: { title: "Unauthorized", detail: "Token expired" },
            });
          }
          twitterMockState.timelineCalls.push({
            kind: "home",
            authMode,
            ...(options?.max_results === undefined
              ? {}
              : { maxResults: options.max_results }),
            ...(options?.pagination_token === undefined
              ? {}
              : { paginationToken: options.pagination_token }),
          });
          const count = options?.max_results ?? 5;
          const page = options?.pagination_token === "page-2" ? 2 : 1;
          return {
            data: buildTimelinePayload("home", count, page),
          };
        },
        userTimeline: async (
          userId: string,
          options?: { max_results?: number; pagination_token?: string },
        ) => {
          if (this.auth === "bad-token") {
            throw new ApiResponseError("Unauthorized", {
              code: 401,
              data: { title: "Unauthorized", detail: "Token expired" },
            });
          }
          twitterMockState.timelineCalls.push({
            kind: "user",
            authMode,
            userId,
            ...(options?.max_results === undefined
              ? {}
              : { maxResults: options.max_results }),
            ...(options?.pagination_token === undefined
              ? {}
              : { paginationToken: options.pagination_token }),
          });
          const count = options?.max_results ?? 5;
          const page = options?.pagination_token === "page-2" ? 2 : 1;
          return {
            data: buildTimelinePayload(`user-${userId}`, count, page),
          };
        },
        userMentionTimeline: async (
          userId: string,
          options?: { max_results?: number; pagination_token?: string },
        ) => {
          if (this.auth === "bad-token") {
            throw new ApiResponseError("Unauthorized", {
              code: 401,
              data: { title: "Unauthorized", detail: "Token expired" },
            });
          }
          twitterMockState.timelineCalls.push({
            kind: "mentions",
            authMode,
            userId,
            ...(options?.max_results === undefined
              ? {}
              : { maxResults: options.max_results }),
            ...(options?.pagination_token === undefined
              ? {}
              : { paginationToken: options.pagination_token }),
          });
          const count = options?.max_results ?? 5;
          const page = options?.pagination_token === "page-2" ? 2 : 1;
          return {
            data: buildTimelinePayload(`mentions-${userId}`, count, page),
          };
        },
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
        tweet: async (
          text: string,
          payload?: { media?: { media_ids?: readonly string[] } },
        ) => {
          const mediaIds = payload?.media?.media_ids ?? [];
          twitterMockState.tweetCalls.push({
            text,
            mediaIds,
            kind: "tweet",
          });
          return {
            data: {
              id: "tweet-1",
              text,
              ...(mediaIds.length === 0 ? {} : { mediaIds }),
            },
          };
        },
        deleteTweet: async (postId: string) => ({
          data: { deleted: true, postId },
        }),
        reply: async (
          text: string,
          replyToPostId: string,
          payload?: { media?: { media_ids?: readonly string[] } },
        ) => {
          const mediaIds = payload?.media?.media_ids ?? [];
          twitterMockState.tweetCalls.push({
            text,
            mediaIds,
            kind: "reply",
          });
          return {
            data: {
              id: "tweet-2",
              text,
              replyToPostId,
              ...(mediaIds.length === 0 ? {} : { mediaIds }),
            },
          };
        },
        quote: async (
          text: string,
          quotedPostId: string,
          payload?: { media?: { media_ids?: readonly string[] } },
        ) => {
          const mediaIds = payload?.media?.media_ids ?? [];
          twitterMockState.tweetCalls.push({
            text,
            mediaIds,
            kind: "quote",
          });
          return {
            data: {
              id: "tweet-3",
              text,
              quotedPostId,
              ...(mediaIds.length === 0 ? {} : { mediaIds }),
            },
          };
        },
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
  twitterMockState.uploadedMedia.length = 0;
  twitterMockState.mediaMetadata.length = 0;
  twitterMockState.tweetCalls.length = 0;
  twitterMockState.timelineCalls.length = 0;
});

describe("resolveConfig", () => {
  test("uses X_GW_ env vars when parameters are omitted", () => {
    process.env["X_GW_TOKEN"] = "env-token";
    process.env["X_GW_TIMEOUT_MS"] = "45000";
    process.env["X_GW_RETRY"] = "3";
    process.env["X_GW_RETRY_BACKOFF"] = "fixed";
    process.env["X_GW_RETRY_BASE_MS"] = "200";
    process.env["X_GW_RETRY_MAX_MS"] = "5000";

    const resolved = resolveConfig();

    expect(resolved.auth.token).toBe("env-token");
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
      retry: {
        retries: 5,
        backoff: "none",
        baseDelayMs: 1,
        maxDelayMs: 2,
      },
    });

    expect(resolved.auth.token).toBe("param-token");
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

    expect(resolved.auth.token).toBeUndefined();
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
    const scopes = await client.authScopes();
    expect(scopes.notes).toContain(
      "Liked-post lookup is currently deferred from the stable CLI, SDK, and project-owned GraphQL contract because the previously attempted live adapter route is not yet verified.",
    );
  });

  test("includes retry exhaustion context and retry-after metadata for retryable public-graph failures", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

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
      client.apiRequest({
        query: "query { postUsage(days: 14) { projectId } }",
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

  test("exposes the stable SDK surface through the owned GraphQL contract", () => {
    const client = createXGatewayClient();

    expect("request" in client).toBe(false);
    expect("apiRequest" in client).toBe(true);
    expect("capabilitiesList" in client).toBe(true);
    expect("authVerify" in client).toBe(true);
    expect("authScopes" in client).toBe(true);
    expect("capabilitiesGet" in client).toBe(true);
    expect("getResolvedConfig" in client).toBe(true);
    expect("likesList" in client).toBe(false);
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

  test("supports paginated timeline fields through the project-owned GraphQL SDK contract", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query:
          'query { searchPosts(query: "  bun  ", maxResults: 10, paginationToken: "  page-2  ") { posts { id author { username } } pageInfo { resultCount previousToken oldestId } } }',
      }),
    ).resolves.toEqual({
      data: {
        searchPosts: {
          posts: [
            { id: "search-bun-11", author: { username: "author_one" } },
            { id: "search-bun-12", author: { username: "author_two" } },
            { id: "search-bun-13", author: { username: "author_one" } },
            { id: "search-bun-14", author: { username: "author_two" } },
            { id: "search-bun-15", author: { username: "author_one" } },
            { id: "search-bun-16", author: { username: "author_two" } },
            { id: "search-bun-17", author: { username: "author_one" } },
            { id: "search-bun-18", author: { username: "author_two" } },
            { id: "search-bun-19", author: { username: "author_one" } },
            { id: "search-bun-20", author: { username: "author_two" } },
          ],
          pageInfo: {
            resultCount: 10,
            previousToken: "page-1",
            oldestId: "search-bun-20",
          },
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

  test("rejects liked-post lookup on the public GraphQL SDK surface until a live route is verified", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query:
          'query { likes(userId: "user-1", limit: 20) { posts { id author { username } } } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL field 'likes' is not part of the current stable x-gateway contract.",
        ),
      }),
    });
  });

  test("accepts canonical postId arguments for project-owned GraphQL post mutations", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: 'mutation { deletePost(postId: "tweet-1") { id deleted } }',
      }),
    ).resolves.toEqual({
      data: {
        deletePost: {
          id: "tweet-1",
          deleted: true,
        },
      },
    });
  });

  test("supports canonical public GraphQL post fetch through the SDK", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query:
          'query { post(id: "post-7") { id text author { username } conversationId } }',
      }),
    ).resolves.toEqual({
      data: {
        post: {
          id: "post-7",
          text: "post post-7",
          author: {
            username: "author_one",
          },
          conversationId: "conversation-1",
        },
      },
    });
  });

  test("supports the remaining project-owned GraphQL post mutation contract through the SDK", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query:
          'mutation { replyToPost(text: "hello", replyToPostId: "post-1") { id text } }',
      }),
    ).resolves.toEqual({
      data: {
        replyToPost: {
          id: "tweet-2",
          text: "hello",
        },
      },
    });

    await expect(
      client.apiRequest({
        query:
          'mutation { quotePost(text: "hello", quotedPostId: "post-2") { id text } }',
      }),
    ).resolves.toEqual({
      data: {
        quotePost: {
          id: "tweet-3",
          text: "hello",
        },
      },
    });

    await expect(
      client.apiRequest({
        query: 'mutation { repostPost(postId: "post-3") { id reposted } }',
      }),
    ).resolves.toEqual({
      data: {
        repostPost: {
          id: "post-3",
          reposted: true,
        },
      },
    });

    await expect(
      client.apiRequest({
        query: 'mutation { unrepostPost(postId: "post-3") { id reposted } }',
      }),
    ).resolves.toEqual({
      data: {
        unrepostPost: {
          id: "post-3",
          reposted: false,
        },
      },
    });
  });

  test("supports attachment-backed public GraphQL post mutations through the SDK", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query:
          'mutation { createPost(text: "hello", attachments: [{ kind: "image", filePath: "/tmp/a.png", altText: "example" }]) { id text } }',
      }),
    ).resolves.toEqual({
      data: {
        createPost: {
          id: "tweet-1",
          text: "hello",
        },
      },
    });

    await expect(
      client.apiRequest({
        query:
          'mutation { replyToPost(text: "hello", replyToPostId: "123", attachments: [{ kind: "image", filePath: "/tmp/b.png" }]) { id text } }',
      }),
    ).resolves.toEqual({
      data: {
        replyToPost: {
          id: "tweet-2",
          text: "hello",
        },
      },
    });

    await expect(
      client.apiRequest({
        query:
          'mutation { quotePost(text: "hello", quotedPostId: "456", attachments: [{ kind: "image", filePath: "/tmp/c.png" }]) { id text } }',
      }),
    ).resolves.toEqual({
      data: {
        quotePost: {
          id: "tweet-3",
          text: "hello",
        },
      },
    });

    expect(twitterMockState.uploadedMedia).toEqual([
      { filePath: "/tmp/a.png", target: "tweet" },
      { filePath: "/tmp/b.png", target: "tweet" },
      { filePath: "/tmp/c.png", target: "tweet" },
    ]);
    expect(twitterMockState.mediaMetadata).toEqual([
      { mediaId: "media-1", altText: "example" },
    ]);
    expect(twitterMockState.tweetCalls).toEqual([
      { text: "hello", mediaIds: ["media-1"], kind: "tweet" },
      { text: "hello", mediaIds: ["media-2"], kind: "reply" },
      { text: "hello", mediaIds: ["media-3"], kind: "quote" },
    ]);
  });

  test("rejects deprecated public GraphQL field names with migration guidance", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: 'query { likedPosts(userId: "user-1", limit: 5) { id } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL field 'likedPosts' is not part of the current stable x-gateway contract.",
        ),
      }),
    });
  });

  test("rejects deprecated mutation id arguments with migration guidance", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: 'mutation { deletePost(id: "tweet-1") { id deleted } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL field 'deletePost' uses 'postId' instead of 'id'.",
        ),
      }),
    });
  });

  test("rejects deprecated repost mutation id arguments with migration guidance", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: 'mutation { repostPost(id: "tweet-1") { id reposted } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL field 'repostPost' uses 'postId' instead of 'id'.",
        ),
      }),
    });

    await expect(
      client.apiRequest({
        query: 'mutation { unrepostPost(id: "tweet-1") { id reposted } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL field 'unrepostPost' uses 'postId' instead of 'id'.",
        ),
      }),
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

  test("rejects unexpected public GraphQL arguments that leak transport-shaped input", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query:
          'query { post(id: "post-1", operationName: "Viewer") { id text } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL field 'post' does not accept argument 'operationName'.",
        ),
      }),
    });
  });

  test("rejects unexpected accountMe arguments on the project-owned GraphQL contract", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: 'query { accountMe(id: "user-1") { id username } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL field 'accountMe' does not accept argument 'id'.",
        ),
      }),
    });
  });

  test("rejects unsupported public GraphQL selection fields instead of ignoring them", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: 'query { post(id: "post-1") { id documentId } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL selection 'post.documentId' is not part of the stable x-gateway contract.",
        ),
      }),
    });
  });

  test("rejects missing projected stable payload fields instead of silently dropping them", () => {
    const plan = createPublicApiRequestPlan(
      {
        query: 'query { post(id: "post-1") { id text } }',
      },
      (message) => new Error(message),
      (fieldName, detail) => new Error(`${fieldName}: ${detail}`),
    );

    expect(() =>
      projectPublicSelection(
        {
          id: "post-1",
        },
        plan.selections,
        "post",
        plan.selectionSchema,
        (fieldName, detail) => new Error(`${fieldName}: ${detail}`),
      ),
    ).toThrowError(/Projected selection 'post\.text' is missing/);
  });

  test("allows omitted optional public payload fields during projection", () => {
    const plan = createPublicApiRequestPlan(
      {
        query:
          'query { post(id: "post-1") { id conversationId author { username } } }',
      },
      (message) => new Error(message),
      (fieldName, detail) => new Error(`${fieldName}: ${detail}`),
    );

    expect(
      projectPublicSelection(
        {
          id: "post-1",
        },
        plan.selections,
        "post",
        plan.selectionSchema,
        (fieldName, detail) => new Error(`${fieldName}: ${detail}`),
      ),
    ).toEqual({
      id: "post-1",
    });
  });

  test("rejects null projected values for required public payload fields", () => {
    const plan = createPublicApiRequestPlan(
      {
        query: 'query { post(id: "post-1") { id text } }',
      },
      (message) => new Error(message),
      (fieldName, detail) => new Error(`${fieldName}: ${detail}`),
    );

    expect(() =>
      projectPublicSelection(
        {
          id: "post-1",
          text: null,
        },
        plan.selections,
        "post",
        plan.selectionSchema,
        (fieldName, detail) => new Error(`${fieldName}: ${detail}`),
      ),
    ).toThrowError(
      /Projected selection 'post\.text' is required by the stable payload schema, but received null/,
    );
  });

  test("rejects object payloads for scalar projected public selections", () => {
    const plan = createPublicApiRequestPlan(
      {
        query: 'query { post(id: "post-1") { id } }',
      },
      (message) => new Error(message),
      (fieldName, detail) => new Error(`${fieldName}: ${detail}`),
    );

    expect(() =>
      projectPublicSelection(
        {
          id: { raw: "post-1" },
        },
        plan.selections,
        "post",
        plan.selectionSchema,
        (fieldName, detail) => new Error(`${fieldName}: ${detail}`),
      ),
    ).toThrowError(/Projected selection 'post\.id' expected a scalar payload/);
  });

  test("rejects scalar payloads for nested projected public selections", () => {
    const plan = createPublicApiRequestPlan(
      {
        query: 'query { post(id: "post-1") { author { username } } }',
      },
      (message) => new Error(message),
      (fieldName, detail) => new Error(`${fieldName}: ${detail}`),
    );

    expect(() =>
      projectPublicSelection(
        {
          author: "not-an-object",
        },
        plan.selections,
        "post",
        plan.selectionSchema,
        (fieldName, detail) => new Error(`${fieldName}: ${detail}`),
      ),
    ).toThrowError(
      /Projected selection 'post\.author' expected an object payload/,
    );
  });

  test("rejects invalid nested selection usage on the project-owned GraphQL contract", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: 'query { post(id: "post-1") { author } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL selection 'post.author' must include a nested selection set.",
        ),
      }),
    });

    await expect(
      client.apiRequest({
        query: 'mutation { createPost(text: "hello") { id { raw } } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL selection 'createPost.id' is scalar and cannot include nested fields.",
        ),
      }),
    });
  });

  test("rejects public GraphQL operation names with explicit migration guidance", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: 'query GetPost { post(id: "post-1") { id } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL operation names are not supported in this implementation slice.",
        ),
      }),
    });
  });

  test("rejects public GraphQL aliases with explicit migration guidance", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: "query { me: accountMe { id username } }",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL aliases are not supported in this implementation slice.",
        ),
      }),
    });
  });

  test("rejects public GraphQL variables, directives, and fragments explicitly", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query: "query { post(id: $postId) { id } }",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL variables are not supported in this implementation slice.",
        ),
      }),
    });

    await expect(
      client.apiRequest({
        query: 'query { post(id: "post-1") @skip(if: true) { id } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL directives are not supported in this implementation slice.",
        ),
      }),
    });

    await expect(
      client.apiRequest({
        query: 'query { post(id: "post-1") { ...PostFields } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "Public GraphQL fragments are not supported in this implementation slice.",
        ),
      }),
    });
  });

  test("parses public GraphQL attachment list and object literals", () => {
    expect(
      parsePublicGraphqlDocument(
        'mutation { createPost(text: "hello", attachments: [{ kind: "image", filePath: "/tmp/a.png", altText: "example" }]) { id text } }',
        (message) => new Error(message),
      ),
    ).toEqual({
      operationType: "mutation",
      field: {
        name: "createPost",
        arguments: {
          text: "hello",
          attachments: [
            {
              kind: "image",
              filePath: "/tmp/a.png",
              altText: "example",
            },
          ],
        },
        selections: [
          { name: "id", selections: [] },
          { name: "text", selections: [] },
        ],
      },
    });
  });

  test("validates attachment object shape in the public GraphQL contract", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    const client = createXGatewayClient();

    await expect(
      client.apiRequest({
        query:
          'mutation { createPost(text: "hello", attachments: [{ kind: "video", filePath: "/tmp/a.mp4" }]) { id } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("must be 'image'"),
      }),
    });

    await expect(
      client.apiRequest({
        query:
          'mutation { createPost(text: "hello", attachments: [{ kind: "image", filePath: "" }]) { id } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("filePath"),
      }),
    });

    await expect(
      client.apiRequest({
        query:
          'mutation { createPost(text: "hello", attachments: [{ kind: "image", filePath: "/tmp/a.png", upstreamId: "1" }]) { id } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("does not accept field 'upstreamId'"),
      }),
    });

    await expect(
      client.apiRequest({
        query: 'mutation { createPost(text: "hello", attachments: []) { id } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("between 1 and 4 attachment objects"),
      }),
    });

    await expect(
      client.apiRequest({
        query:
          'mutation { createPost(text: "hello", attachments: [{ kind: "image", filePath: "/tmp/a.png", altText: null }]) { id } }',
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("altText"),
      }),
    });

    await expect(
      client.apiRequest({
        query: `mutation { createPost(text: "hello", attachments: [{ kind: "image", filePath: "/tmp/a.png", altText: "${"x".repeat(1001)}" }]) { id } }`,
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("between 1 and 1000 characters"),
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

  test("rejects missing positional GraphQL documents", async () => {
    await expect(
      executeCli(["graphql", "query"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining(
          "graphql query requires a single shell-quoted GraphQL document positional argument",
        ),
      }),
    });
  });

  test("rejects bare numeric flags instead of coercing them to true", async () => {
    await expect(
      executeCli(["graphql", "query", "query { accountMe { id } }", "--retry"], {
        commandName: "x-gateway",
        surface: "full",
      }),
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
          "query",
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

  test("honors X_GW_CONFIG_MODE from env when CLI flags omit config-mode", async () => {
    process.env["X_GW_CONFIG_MODE"] = "params";
    process.env["X_GW_TOKEN"] = "env-token";

    await expect(
      executeCli(["graphql", "query", "query { accountMe { id } }"], {
        commandName: "x-gateway",
        surface: "full",
      }),
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

  test("rejects removed legacy convenience commands through the CLI", async () => {
    await expect(
      executeCli(["account", "me"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
        details: expect.stringContaining(
          "no longer part of the supported CLI surface",
        ),
      }),
    });

    await expect(
      executeCli(["usage", "tweets", "--days", "14"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
        remediations: expect.arrayContaining([
          expect.stringContaining("graphql query '<query>'"),
        ]),
      }),
    });

    await expect(
      executeCli(["timeline", "search", "--query", "bun"], {
        commandName: "x-gateway-reader",
        surface: "reader",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
  });

  test("supports the project-owned GraphQL contract through the CLI", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    await expect(
      executeCli(
        ["graphql", "query", "query { accountMe { id username } }"],
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

  test("supports postUsage through the project-owned GraphQL CLI contract", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    const fetchMock = vi.fn(async () => {
      return new Response(
        JSON.stringify({
          data: {
            cap_reset_day: 31,
            daily_client_app_usage: [
              {
                client_app_id: "client-app-1",
                usage: [
                  {
                    date: "2026-04-01T00:00:00.000Z",
                    usage: 12,
                  },
                ],
                usage_result_count: 1,
              },
            ],
            daily_project_usage: {
              project_id: "project-1",
              usage: [
                {
                  date: "2026-04-01T00:00:00.000Z",
                  usage: 12,
                },
              ],
            },
            project_cap: 5000,
            project_id: "project-1",
            project_usage: 12,
          },
        }),
        {
          status: 200,
          headers: {
            "content-type": "application/json",
          },
        },
      );
    });
    globalThis.fetch = fetchMock as typeof fetch;

    await expect(
      executeCli(
        [
          "graphql",
          "query",
          "query { postUsage(days: 14) { projectId projectUsage dailyProjectUsage { usage { date usage } } } }",
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).resolves.toEqual({
      data: {
        postUsage: {
          projectId: "project-1",
          projectUsage: 12,
          dailyProjectUsage: {
            usage: [
              {
                date: "2026-04-01T00:00:00.000Z",
                usage: 12,
              },
            ],
          },
        },
      },
    });
  });

  test("supports paginated timeline fields through the project-owned GraphQL CLI contract", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    await expect(
      executeCli(
        [
          "graphql",
          "query",
          'query { userTimeline(userId: "  user-42  ", maxResults: 5, paginationToken: "  page-2  ") { posts { id } pageInfo { resultCount previousToken } } }',
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).resolves.toEqual({
      data: {
        userTimeline: {
          posts: [
            { id: "user-user-42-6" },
            { id: "user-user-42-7" },
            { id: "user-user-42-8" },
            { id: "user-user-42-9" },
            { id: "user-user-42-10" },
          ],
          pageInfo: {
            resultCount: 5,
            previousToken: "page-1",
          },
        },
      },
    });
  });

  test("rejects liked-post lookup on the public GraphQL CLI surface until a live route is verified", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    await expect(
      executeCli(
        [
          "graphql",
          "query",
          'query { likes(userId: "user-1", limit: 2) { posts { id text } } }',
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
          "Public GraphQL field 'likes' is not part of the current stable x-gateway contract.",
        ),
      }),
    });
  });

  test("rejects deprecated public GraphQL field names through the CLI with migration guidance", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    await expect(
      executeCli(
        [
          "graphql",
          "query",
          'query { likedPosts(userId: "user-1", limit: 2) { id } }',
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
          "Public GraphQL field 'likedPosts' is not part of the current stable x-gateway contract.",
        ),
      }),
    });
  });

  test("supports canonical public GraphQL post fetch through the CLI", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    await expect(
      executeCli(
        [
          "graphql",
          "query",
          'query { post(id: "post-7") { id text author { username } } }',
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).resolves.toEqual({
      data: {
        post: {
          id: "post-7",
          text: "post post-7",
          author: {
            username: "author_one",
          },
        },
      },
    });
  });

  test("supports the remaining project-owned GraphQL post mutation contract through the CLI", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    await expect(
      executeCli(
        [
          "graphql",
          "query",
          'mutation { repostPost(postId: "post-3") { id reposted } }',
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).resolves.toEqual({
      data: {
        repostPost: {
          id: "post-3",
          reposted: true,
        },
      },
    });

    await expect(
      executeCli(
        [
          "graphql",
          "query",
          'mutation { unrepostPost(postId: "post-3") { id reposted } }',
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).resolves.toEqual({
      data: {
        unrepostPost: {
          id: "post-3",
          reposted: false,
        },
      },
    });
  });

  test("supports attachment-backed public GraphQL post mutations through the CLI", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    await expect(
      executeCli(
        [
          "graphql",
          "query",
          'mutation { createPost(text: "hello", attachments: [{ kind: "image", filePath: "/tmp/a.png", altText: "example" }]) { id text } }',
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).resolves.toEqual({
      data: {
        createPost: {
          id: "tweet-1",
          text: "hello",
        },
      },
    });

    await expect(
      executeCli(
        [
          "graphql",
          "query",
          'mutation { replyToPost(text: "hello", replyToPostId: "123", attachments: [{ kind: "image", filePath: "/tmp/b.png" }]) { id text } }',
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).resolves.toEqual({
      data: {
        replyToPost: {
          id: "tweet-2",
          text: "hello",
        },
      },
    });

    await expect(
      executeCli(
        [
          "graphql",
          "query",
          'mutation { quotePost(text: "hello", quotedPostId: "456", attachments: [{ kind: "image", filePath: "/tmp/c.png" }]) { id text } }',
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).resolves.toEqual({
      data: {
        quotePost: {
          id: "tweet-3",
          text: "hello",
        },
      },
    });
  });

  test("rejects deprecated mutation id arguments through the CLI with migration guidance", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    await expect(
      executeCli(
        [
          "graphql",
          "query",
          'mutation { repostPost(id: "post-3") { id reposted } }',
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
          "Public GraphQL field 'repostPost' uses 'postId' instead of 'id'.",
        ),
      }),
    });
  });

  test("rejects unexpected accountMe arguments through the CLI", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    await expect(
      executeCli(
        [
          "graphql",
          "query",
          'query { accountMe(id: "user-1") { id username } }',
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
          "Public GraphQL field 'accountMe' does not accept argument 'id'.",
        ),
      }),
    });
  });

  test("rejects unsupported public GraphQL args and selections through the CLI", async () => {
    process.env["X_GW_TOKEN"] = "bearer-token";

    await expect(
      executeCli(
        [
          "graphql",
          "query",
          'query { post(id: "post-1", operationName: "Viewer") { id } }',
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
          "Public GraphQL field 'post' does not accept argument 'operationName'.",
        ),
      }),
    });

    await expect(
      executeCli(
        [
          "graphql",
          "query",
          'query { likes(userId: "user-1") { posts { id features } } }',
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
          "Public GraphQL field 'likes' is not part of the current stable x-gateway contract.",
        ),
      }),
    });
  });

  test("rejects removed api request aliases with migration guidance", async () => {
    await expect(
      executeCli(
        [
          "api",
          "request",
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
        remediations: expect.arrayContaining([
          expect.stringContaining("graphql query '<query>'"),
        ]),
      }),
    });
  });

  test("rejects removed post convenience commands through the CLI on both surfaces", async () => {
    await expect(
      executeCli(["post", "get", "--post-id", "post-7"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });

    await expect(
      executeCli(["post", "get", "--post-id", "post-8"], {
        commandName: "x-gateway-reader",
        surface: "reader",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
      }),
    });
  });

  test("rejects deferred likes list through the CLI on both surfaces", async () => {
    process.env["X_GW_CONSUMER_KEY"] = "ck";
    process.env["X_GW_CONSUMER_SECRET"] = "cs";
    process.env["X_GW_ACCESS_TOKEN"] = "at";
    process.env["X_GW_ACCESS_TOKEN_SECRET"] = "ats";

    await expect(
      executeCli(["likes", "list", "--user-id", "user-7", "--limit", "1"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
        details: expect.stringContaining(
          "does not have a reviewed capability adapter",
        ),
      }),
    });

    await expect(
      executeCli(["likes", "list", "--user-id", "user-8"], {
        commandName: "x-gateway-reader",
        surface: "reader",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
        details: expect.stringContaining(
          "does not have a reviewed capability adapter",
        ),
      }),
    });
  });

  test("omits removed legacy command groups from reader usage output", async () => {
    await expect(
      executeCli([], {
        commandName: "x-gateway-reader",
        surface: "reader",
      }),
    ).resolves.not.toContain("post get");
    await expect(
      executeCli([], {
        commandName: "x-gateway-reader",
        surface: "reader",
      }),
    ).resolves.not.toContain("post create");
    await expect(
      executeCli([], {
        commandName: "x-gateway-reader",
        surface: "reader",
      }),
    ).resolves.not.toContain("usage tweets");
  });

  test("lists graphql schema in usage output for both CLI surfaces", async () => {
    await expect(
      executeCli([], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).resolves.toContain("graphql schema");
    await expect(
      executeCli([], {
        commandName: "x-gateway-reader",
        surface: "reader",
      }),
    ).resolves.toContain("graphql schema");
  });

  test("prints the full public GraphQL schema through the CLI", async () => {
    const expectedSchema = printSchema(PUBLIC_GRAPHQL_SCHEMA);

    await expect(
      executeCli(["graphql", "schema"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).resolves.toBe(expectedSchema);
    await expect(
      executeCli(["graphql", "schema"], {
        commandName: "x-gateway-reader",
        surface: "reader",
      }),
    ).resolves.toBe(expectedSchema);
  });

  test("rejects removed write-oriented convenience commands through the CLI", async () => {
    await expect(
      executeCli(["post", "create", "--text", "hello"], {
        commandName: "x-gateway",
        surface: "full",
      }),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "UNSUPPORTED",
        details: expect.stringContaining(
          "no longer part of the supported CLI surface",
        ),
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
    const usageTweets = client.capabilitiesGet("usage.tweets");
    const timelineSearch = client.capabilitiesGet("timeline.search");
    const timelineHome = client.capabilitiesGet("timeline.home");
    const deferredSocial = client.capabilitiesGet("social.follows");
    const stableLikes = client.capabilitiesGet("likes.list");
    const rawGraphql = client.capabilitiesGet("graphql.request");

    expect(capability.transportStrategy).toBe("rest-v2");
    expect(capability.publicOperationName).toBe("deletePost");
    expect(capability.surfaceCategory).toBe("stable-contract");
    expect(capability.accessType).toBe("write");
    expect(capability.preferredTransport).toBe("rest-v2");
    expect(capability.authModes).toEqual(["oauth1"]);
    expect(usageTweets.transportStrategy).toBe("rest-v2");
    expect(usageTweets.publicOperationName).toBe("postUsage");
    expect(usageTweets.authModes).toEqual(["bearer"]);
    expect(usageTweets.notes).toContain("usage counts");
    expect(stableLikes.status).toBe("blocked_by_plan");
    expect(stableLikes.publicOperationName).toBeUndefined();
    expect(stableLikes.surfaceCategory).toBe("deferred");
    expect(stableLikes.transportStrategy).toBe("rest-v2");
    expect(stableLikes.authModes).toEqual(["oauth1"]);
    expect(rawGraphql.surfaceCategory).toBe("escape-hatch");
    expect(timelineSearch.publicOperationName).toBe("searchPosts");
    expect(timelineSearch.surfaceCategory).toBe("stable-contract");
    expect(timelineSearch.status).toBe("implemented");
    expect(timelineSearch.transportStrategy).toBe("rest-v2");
    expect(timelineHome.publicOperationName).toBe("homeTimeline");
    expect(timelineHome.surfaceCategory).toBe("stable-contract");
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
      "homeTimeline",
      "mentionsTimeline",
      "post",
      "postUsage",
      "quotePost",
      "replyToPost",
      "repostPost",
      "searchPosts",
      "unrepostPost",
      "userTimeline",
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
    process.env["X_GW_TOKEN"] = "bearer-token";
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
          "query",
          "query { postUsage(days: 14) { projectId } }",
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

  test("rejects removed raw-graphql-specific flags on the public CLI surface", async () => {
    await expect(
      executeCli(
        [
          "graphql",
          "query",
          "query { accountMe { id } }",
          "--graphql-base-url",
          "https://cli.example/graphql",
        ],
        {
          commandName: "x-gateway",
          surface: "full",
        },
      ),
    ).rejects.toMatchObject({
      payload: expect.objectContaining({
        code: "VALIDATION_ERROR",
        details: expect.stringContaining("Unknown flag --graphql-base-url"),
      }),
    });
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

  test("rejects removed api-base flag aliases instead of silently accepting them", async () => {
    await expect(
      executeCli(
        [
          "graphql",
          "query",
          "query { accountMe { id } }",
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
        details: expect.stringContaining("Unknown flag --api-base-url"),
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
