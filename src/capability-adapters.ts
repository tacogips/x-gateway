import {
  TwitterApi,
  TwitterV2IncludesHelper,
  type SendTweetV2Params,
  type TweetV2,
  type TweetV2SingleResult,
  type Tweetv2FieldsParams,
  type UserV2,
} from "twitter-api-v2";
import type {
  XGatewayAccountProfile,
  XGatewayAuthConfig,
  XGatewayError,
  XGatewayErrorPayload,
  XGatewayPostAttachmentInput,
  XGatewayPostPage,
  XGatewayPostCreateOptions,
  XGatewayPostDeleteOptions,
  XGatewayPostGetOptions,
  XGatewayPostLookupResult,
  XGatewayPostQuoteOptions,
  XGatewayPostReferenceRelation,
  XGatewayPostReplyOptions,
  XGatewayPostRepostOptions,
  XGatewayReferencedPost,
  XGatewayPostSummary,
  XGatewayTimelinePageOptions,
  XGatewayTimelineSearchOptions,
  XGatewayTimelineUserOptions,
} from "./lib";
import type {
  XGatewayReadCapabilityAdapter,
  XGatewayStablePostingAdapter,
} from "./stable-capability-executor";
import { validatePostAttachments } from "./post-attachments";

const POST_LOOKUP_FIELDS: Partial<Tweetv2FieldsParams> = {
  expansions: [
    "author_id",
    "referenced_tweets.id",
    "referenced_tweets.id.author_id",
  ],
  "tweet.fields": [
    "author_id",
    "conversation_id",
    "created_at",
    "in_reply_to_user_id",
    "referenced_tweets",
  ],
  "user.fields": ["id", "name", "username"],
} as const;

type CapabilityAdapterDependencies = Readonly<{
  auth: XGatewayAuthConfig;
  createError: (payload: XGatewayErrorPayload) => XGatewayError;
  createValidationError: (message: string) => XGatewayError;
  ensureRequired: (value: string | undefined, fieldName: string) => string;
}>;

type V2TimelineMeta = Readonly<{
  result_count?: number;
  next_token?: string;
  previous_token?: string;
  newest_id?: string;
  oldest_id?: string;
}>;

type V2TimelinePayload = Readonly<{
  data?: readonly TweetV2[];
  includes?: Readonly<{
    tweets?: readonly TweetV2[];
    users?: readonly UserV2[];
  }>;
  meta?: V2TimelineMeta;
}>;

function isNonEmpty(value: string | undefined): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function hasOauth1(auth: XGatewayAuthConfig): boolean {
  return Boolean(
    auth.consumerKey &&
      auth.consumerSecret &&
      auth.accessToken &&
      auth.accessTokenSecret,
  );
}

function hasBearerToken(auth: XGatewayAuthConfig): boolean {
  return isNonEmpty(auth.token);
}

function isSupportedPostReferenceRelation(
  input: string,
): input is XGatewayPostReferenceRelation {
  return input === "replied_to" || input === "quoted" || input === "retweeted";
}

function mapOptionalAccountProfile(
  user: UserV2 | undefined,
): XGatewayAccountProfile | undefined {
  if (!user) {
    return undefined;
  }

  return {
    id: user.id,
    username: user.username,
    name: user.name,
  };
}

function mapPostSummary(
  tweet: TweetV2,
  includesHelper: TwitterV2IncludesHelper,
): XGatewayPostSummary {
  const author = mapOptionalAccountProfile(includesHelper.author(tweet));
  return {
    id: tweet.id,
    text: tweet.text,
    ...(tweet.created_at === undefined ? {} : { createdAt: tweet.created_at }),
    ...(tweet.conversation_id === undefined
      ? {}
      : { conversationId: tweet.conversation_id }),
    ...(tweet.in_reply_to_user_id === undefined
      ? {}
      : { replyToUserId: tweet.in_reply_to_user_id }),
    ...(author === undefined ? {} : { author }),
  };
}

function mapPostLookupResult(
  response: TweetV2SingleResult,
): XGatewayPostLookupResult {
  const includesHelper = new TwitterV2IncludesHelper(response);
  const referencedPosts: XGatewayReferencedPost[] = [];

  for (const reference of response.data.referenced_tweets ?? []) {
    if (!isSupportedPostReferenceRelation(reference.type)) {
      continue;
    }

    const referencedTweet = includesHelper.tweetById(reference.id);
    if (!referencedTweet) {
      continue;
    }

    referencedPosts.push({
      relation: reference.type,
      ...mapPostSummary(referencedTweet, includesHelper),
    });
  }

  return {
    post: mapPostSummary(response.data, includesHelper),
    referencedPosts,
  };
}

function mapPostPage(response: V2TimelinePayload): XGatewayPostPage {
  const tweets = response.data ?? [];
  const includesHelper = new TwitterV2IncludesHelper({
    ...(response.data === undefined ? {} : { data: [...response.data] }),
    ...(response.includes === undefined
      ? {}
      : {
          includes: {
            ...(response.includes.tweets === undefined
              ? {}
              : { tweets: [...response.includes.tweets] }),
            ...(response.includes.users === undefined
              ? {}
              : { users: [...response.includes.users] }),
          },
        }),
  });
  const meta = response.meta;
  return {
    posts: tweets.map((tweet) => mapPostSummary(tweet, includesHelper)),
    pageInfo: {
      resultCount: meta?.result_count ?? tweets.length,
      ...(meta?.next_token === undefined ? {} : { nextToken: meta.next_token }),
      ...(meta?.previous_token === undefined
        ? {}
        : { previousToken: meta.previous_token }),
      ...(meta?.newest_id === undefined ? {} : { newestId: meta.newest_id }),
      ...(meta?.oldest_id === undefined ? {} : { oldestId: meta.oldest_id }),
    },
  };
}

function mapBearerAccountProfile(
  response: Readonly<{ data?: unknown }>,
  createError: (payload: XGatewayErrorPayload) => XGatewayError,
): XGatewayAccountProfile {
  const user =
    typeof response.data === "object" && response.data !== null
      ? (response.data as {
          id?: unknown;
          username?: unknown;
          name?: unknown;
        })
      : undefined;
  if (
    !user ||
    !isNonEmpty(typeof user.id === "string" ? user.id : undefined) ||
    !isNonEmpty(typeof user.username === "string" ? user.username : undefined)
  ) {
    throw createError({
      code: "UPSTREAM_FAILURE",
      summary: "Authenticated account lookup returned incomplete data",
      details:
        "The upstream response did not contain the expected id/username fields.",
      likelyCauses: [
        "The upstream endpoint returned an unexpected payload shape",
        "The credential lacks permission to read the authenticated user profile",
      ],
      remediations: [
        "Retry with a credential that includes users.read scope.",
        "Inspect the upstream response or update the adapter for the returned schema.",
      ],
      classification: "upstream",
      retryable: false,
    });
  }
  const id = user.id as string;
  const username = user.username as string;
  return {
    id,
    username,
    name: typeof user.name === "string" ? user.name : "",
  };
}

type SupportedMediaIds =
  | [string]
  | [string, string]
  | [string, string, string]
  | [string, string, string, string];

function toSendTweetMediaIds(
  mediaIds: readonly string[],
): SupportedMediaIds | undefined {
  if (mediaIds.length === 0) {
    return undefined;
  }
  return mediaIds as SupportedMediaIds;
}

function validateOptionalPaginationToken(
  value: string | undefined,
  fieldName: string,
  createValidationError: (message: string) => XGatewayError,
): string | undefined {
  if (value === undefined) {
    return undefined;
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw createValidationError(`${fieldName} must be a non-empty string.`);
  }
  return trimmed;
}

function validateOptionalMaxResults(
  value: number | undefined,
  fieldName: string,
  minimum: number,
  maximum: number,
  createValidationError: (message: string) => XGatewayError,
): number | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw createValidationError(
      `${fieldName} must be an integer between ${minimum} and ${maximum}.`,
    );
  }
  return value;
}

export function createCapabilityAdapterFactories(
  dependencies: CapabilityAdapterDependencies,
): Readonly<{
  createReadAdapter: (
    authMode: "oauth1" | "bearer",
  ) => XGatewayReadCapabilityAdapter;
  createStablePostingAdapter: (
    authMode: "oauth1" | "bearer",
  ) => XGatewayStablePostingAdapter;
}> {
  function createOauth1RestClient(): TwitterApi {
    if (!hasOauth1(dependencies.auth)) {
      throw dependencies.createError({
        code: "AUTH_MISSING",
        summary: "Authentication configuration missing",
        details:
          "OAuth1-backed adapters require consumer key/secret plus access token/secret credentials.",
        likelyCauses: [
          "OAuth1 credentials were not fully configured",
          "Credential values were empty after environment resolution",
        ],
        remediations: [
          "Set X_GW_CONSUMER_KEY, X_GW_CONSUMER_SECRET, X_GW_ACCESS_TOKEN, and X_GW_ACCESS_TOKEN_SECRET for OAuth1 usage.",
        ],
        classification: "auth",
        retryable: false,
      });
    }
    return new TwitterApi({
      appKey: dependencies.auth.consumerKey!,
      appSecret: dependencies.auth.consumerSecret!,
      accessToken: dependencies.auth.accessToken!,
      accessSecret: dependencies.auth.accessTokenSecret!,
    });
  }

  function createBearerRestClient(): TwitterApi {
    if (!hasBearerToken(dependencies.auth)) {
      throw dependencies.createError({
        code: "AUTH_MISSING",
        summary: "Authentication configuration missing",
        details: "Bearer-backed adapters require X_GW_TOKEN or auth.token.",
        likelyCauses: [
          "Bearer token was not configured",
          "Credential values were empty after environment resolution",
        ],
        remediations: ["Set X_GW_TOKEN for bearer-token usage."],
        classification: "auth",
        retryable: false,
      });
    }
    return new TwitterApi(dependencies.auth.token!);
  }

  function createOauth1ReadCapabilityAdapter(): XGatewayReadCapabilityAdapter {
    const client = createOauth1RestClient();
    const timelineHome = async (
      options: XGatewayTimelinePageOptions,
    ): Promise<XGatewayPostPage> => {
      const response = await client.v2.homeTimeline({
        ...(validateOptionalMaxResults(
          options.maxResults,
          "maxResults",
          5,
          100,
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { max_results: options.maxResults }),
        ...(validateOptionalPaginationToken(
          options.paginationToken,
          "paginationToken",
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { pagination_token: options.paginationToken }),
        ...POST_LOOKUP_FIELDS,
      });
      return mapPostPage(response.data as V2TimelinePayload);
    };
    const timelineUser = async (
      options: XGatewayTimelineUserOptions,
    ): Promise<XGatewayPostPage> => {
      const userId = dependencies.ensureRequired(options.userId, "userId");
      const response = await client.v2.userTimeline(userId, {
        ...(validateOptionalMaxResults(
          options.maxResults,
          "maxResults",
          5,
          100,
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { max_results: options.maxResults }),
        ...(validateOptionalPaginationToken(
          options.paginationToken,
          "paginationToken",
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { pagination_token: options.paginationToken }),
        ...POST_LOOKUP_FIELDS,
      });
      return mapPostPage(response.data as V2TimelinePayload);
    };
    const timelineMentions = async (
      options: XGatewayTimelineUserOptions,
    ): Promise<XGatewayPostPage> => {
      const userId = dependencies.ensureRequired(options.userId, "userId");
      const response = await client.v2.userMentionTimeline(userId, {
        ...(validateOptionalMaxResults(
          options.maxResults,
          "maxResults",
          5,
          100,
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { max_results: options.maxResults }),
        ...(validateOptionalPaginationToken(
          options.paginationToken,
          "paginationToken",
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { pagination_token: options.paginationToken }),
        ...POST_LOOKUP_FIELDS,
      });
      return mapPostPage(response.data as V2TimelinePayload);
    };
    const timelineSearch = async (
      options: XGatewayTimelineSearchOptions,
    ): Promise<XGatewayPostPage> => {
      const query = dependencies.ensureRequired(options.query, "query");
      const response = await client.v2.search(query, {
        ...(validateOptionalMaxResults(
          options.maxResults,
          "maxResults",
          10,
          100,
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { max_results: options.maxResults }),
        ...(validateOptionalPaginationToken(
          options.paginationToken,
          "paginationToken",
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { next_token: options.paginationToken }),
        ...POST_LOOKUP_FIELDS,
      });
      return mapPostPage(response.data as V2TimelinePayload);
    };
    const postGet = async (
      options: XGatewayPostGetOptions,
    ): Promise<XGatewayPostLookupResult> => {
      const postId = dependencies.ensureRequired(options.postId, "postId");
      const response = await client.v2.singleTweet(postId, POST_LOOKUP_FIELDS);
      return mapPostLookupResult(response);
    };

    return {
      adapterKind: "rest-oauth1",
      accountMe: async () => {
        const user = await client.v1.verifyCredentials({
          include_entities: false,
          skip_status: true,
        });
        return {
          id: user.id_str,
          username: user.screen_name,
          name: user.name,
        };
      },
      postGet,
      timelineSearch,
      timelineHome,
      timelineUser,
      timelineMentions,
    };
  }

  function createBearerReadCapabilityAdapter(): XGatewayReadCapabilityAdapter {
    const client = createBearerRestClient();
    const timelineHome = async (
      options: XGatewayTimelinePageOptions,
    ): Promise<XGatewayPostPage> => {
      const response = await client.v2.homeTimeline({
        ...(validateOptionalMaxResults(
          options.maxResults,
          "maxResults",
          5,
          100,
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { max_results: options.maxResults }),
        ...(validateOptionalPaginationToken(
          options.paginationToken,
          "paginationToken",
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { pagination_token: options.paginationToken }),
        ...POST_LOOKUP_FIELDS,
      });
      return mapPostPage(response.data as V2TimelinePayload);
    };
    const timelineUser = async (
      options: XGatewayTimelineUserOptions,
    ): Promise<XGatewayPostPage> => {
      const userId = dependencies.ensureRequired(options.userId, "userId");
      const response = await client.v2.userTimeline(userId, {
        ...(validateOptionalMaxResults(
          options.maxResults,
          "maxResults",
          5,
          100,
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { max_results: options.maxResults }),
        ...(validateOptionalPaginationToken(
          options.paginationToken,
          "paginationToken",
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { pagination_token: options.paginationToken }),
        ...POST_LOOKUP_FIELDS,
      });
      return mapPostPage(response.data as V2TimelinePayload);
    };
    const timelineMentions = async (
      options: XGatewayTimelineUserOptions,
    ): Promise<XGatewayPostPage> => {
      const userId = dependencies.ensureRequired(options.userId, "userId");
      const response = await client.v2.userMentionTimeline(userId, {
        ...(validateOptionalMaxResults(
          options.maxResults,
          "maxResults",
          5,
          100,
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { max_results: options.maxResults }),
        ...(validateOptionalPaginationToken(
          options.paginationToken,
          "paginationToken",
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { pagination_token: options.paginationToken }),
        ...POST_LOOKUP_FIELDS,
      });
      return mapPostPage(response.data as V2TimelinePayload);
    };
    const timelineSearch = async (
      options: XGatewayTimelineSearchOptions,
    ): Promise<XGatewayPostPage> => {
      const query = dependencies.ensureRequired(options.query, "query");
      const response = await client.v2.search(query, {
        ...(validateOptionalMaxResults(
          options.maxResults,
          "maxResults",
          10,
          100,
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { max_results: options.maxResults }),
        ...(validateOptionalPaginationToken(
          options.paginationToken,
          "paginationToken",
          dependencies.createValidationError,
        ) === undefined
          ? {}
          : { next_token: options.paginationToken }),
        ...POST_LOOKUP_FIELDS,
      });
      return mapPostPage(response.data as V2TimelinePayload);
    };
    const postGet = async (
      options: XGatewayPostGetOptions,
    ): Promise<XGatewayPostLookupResult> => {
      const postId = dependencies.ensureRequired(options.postId, "postId");
      const response = await client.v2.singleTweet(postId, POST_LOOKUP_FIELDS);
      return mapPostLookupResult(response);
    };

    return {
      adapterKind: "rest-bearer",
      accountMe: async () => {
        const response = await client.v2.me({
          "user.fields": ["id", "name", "username"],
        });
      return mapBearerAccountProfile(response, dependencies.createError);
      },
      postGet,
      timelineSearch,
      timelineHome,
      timelineUser,
      timelineMentions,
    };
  }

  function createOauth1StablePostingAdapter(): XGatewayStablePostingAdapter {
    const client = createOauth1RestClient();

    const getLoggedUserId = async (): Promise<string> => {
      const user = await client.v1.verifyCredentials({
        include_entities: false,
        skip_status: true,
      });
      return user.id_str;
    };

    const uploadAttachments = async (
      attachments: readonly XGatewayPostAttachmentInput[] | undefined,
    ): Promise<SupportedMediaIds | undefined> => {
      const normalizedAttachments =
        validatePostAttachments(attachments, {
          createValidationError: dependencies.createValidationError,
          messages: {
            invalidCollection:
              "attachments must contain between 1 and 4 items when provided.",
            invalidItem: (index) =>
              `attachments[${index}] must be an object with kind, filePath, and optional altText.`,
            unexpectedField: (index, key) =>
              `attachments[${index}] does not accept field '${key}'. Supported fields: kind, filePath, altText.`,
            invalidKind: (index) =>
              `attachments[${index}].kind must be 'image' in the current reviewed posting slice.`,
            invalidFilePath: (index) =>
              `attachments[${index}].filePath must be a non-empty string.`,
            invalidAltText: {
              empty: (index) =>
                `attachments[${index}].altText must be between 1 and 1000 characters when provided.`,
              tooLong: (index) =>
                `attachments[${index}].altText must be between 1 and 1000 characters when provided.`,
            },
          },
        }) ?? [];
      const mediaIds: string[] = [];
      for (const attachment of normalizedAttachments) {
        const mediaId = await client.v1.uploadMedia(attachment.filePath, {
          target: "tweet",
        });
        if (attachment.altText !== undefined) {
          await client.v1.createMediaMetadata(mediaId, {
            alt_text: {
              text: attachment.altText,
            },
          });
        }
        mediaIds.push(mediaId);
      }
      return toSendTweetMediaIds(mediaIds);
    };

    const buildMediaPayload = async (
      attachments: readonly XGatewayPostAttachmentInput[] | undefined,
    ): Promise<Partial<SendTweetV2Params> | undefined> => {
      const mediaIds = await uploadAttachments(attachments);
      if (mediaIds === undefined) {
        return undefined;
      }
      return {
        media: {
          media_ids: mediaIds,
        },
      };
    };

    return {
      adapterKind: "rest-oauth1",
      postCreate: async (options: XGatewayPostCreateOptions) => {
        const text = dependencies.ensureRequired(options.text, "text");
        return client.v2.tweet(
          text,
          await buildMediaPayload(options.attachments),
        );
      },
      postDelete: async (options: XGatewayPostDeleteOptions) => {
        const postId = dependencies.ensureRequired(options.postId, "postId");
        return client.v2.deleteTweet(postId);
      },
      postReply: async (options: XGatewayPostReplyOptions) => {
        const text = dependencies.ensureRequired(options.text, "text");
        const replyToPostId = dependencies.ensureRequired(
          options.replyToPostId,
          "replyToPostId",
        );
        return client.v2.reply(
          text,
          replyToPostId,
          await buildMediaPayload(options.attachments),
        );
      },
      postQuote: async (options: XGatewayPostQuoteOptions) => {
        const text = dependencies.ensureRequired(options.text, "text");
        const quotedPostId = dependencies.ensureRequired(
          options.quotedPostId,
          "quotedPostId",
        );
        return client.v2.quote(
          text,
          quotedPostId,
          await buildMediaPayload(options.attachments),
        );
      },
      postRepost: async (options: XGatewayPostRepostOptions) => {
        const postId = dependencies.ensureRequired(options.postId, "postId");
        const loggedUserId = await getLoggedUserId();
        return client.v2.retweet(loggedUserId, postId);
      },
      postUndoRepost: async (options: XGatewayPostRepostOptions) => {
        const postId = dependencies.ensureRequired(options.postId, "postId");
        const loggedUserId = await getLoggedUserId();
        return client.v2.unretweet(loggedUserId, postId);
      },
    };
  }

  return {
    createReadAdapter: (authMode) =>
      authMode === "oauth1"
        ? createOauth1ReadCapabilityAdapter()
        : createBearerReadCapabilityAdapter(),
    createStablePostingAdapter: (authMode) => {
      if (authMode !== "oauth1") {
        throw dependencies.createError({
          code: "INTERNAL_ERROR",
          summary: "Stable posting adapter auth mismatch",
          details:
            "The planner selected a non-OAuth1 auth mode for the stable posting adapter, but no reviewed non-OAuth1 posting adapter exists.",
          likelyCauses: [
            "Planner metadata advertised an unimplemented stable posting auth route",
          ],
          remediations: [
            "Restrict stable posting routes to reviewed OAuth1 adapters until another auth path is implemented.",
          ],
          classification: "internal",
          retryable: false,
        });
      }
      return createOauth1StablePostingAdapter();
    },
  };
}
