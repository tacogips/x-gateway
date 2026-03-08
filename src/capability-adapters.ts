import {
  TwitterApi,
  TwitterV2IncludesHelper,
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
  XGatewayLikesListOptions,
  XGatewayLikesListResult,
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
} from "./lib";
import type {
  XGatewayReadCapabilityAdapter,
  XGatewayStablePostingAdapter,
} from "./stable-capability-executor";

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

function validateLikesListLimit(
  limit: number | undefined,
  createValidationError: (message: string) => XGatewayError,
): number | undefined {
  if (limit === undefined) {
    return undefined;
  }
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
    throw createValidationError("limit must be an integer between 1 and 100.");
  }
  return limit;
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

function mapLikesListResult(
  userId: string,
  tweets: readonly TweetV2[],
  includesHelper: TwitterV2IncludesHelper,
): XGatewayLikesListResult {
  return {
    userId,
    posts: tweets.map((tweet) => mapPostSummary(tweet, includesHelper)),
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
    const postGet = async (
      options: XGatewayPostGetOptions,
    ): Promise<XGatewayPostLookupResult> => {
      const postId = dependencies.ensureRequired(options.postId, "postId");
      const response = await client.v2.singleTweet(postId, POST_LOOKUP_FIELDS);
      return mapPostLookupResult(response);
    };
    const likesList = async (
      options: XGatewayLikesListOptions,
    ): Promise<XGatewayLikesListResult> => {
      const userId = dependencies.ensureRequired(options.userId, "userId");
      const limit = validateLikesListLimit(
        options.limit,
        dependencies.createValidationError,
      );
      const response = await client.v2.userLikedTweets(userId, {
        ...POST_LOOKUP_FIELDS,
        ...(limit === undefined ? {} : { max_results: limit }),
      });
      return mapLikesListResult(userId, response.tweets, response.includes);
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
      likesList,
    };
  }

  function createBearerReadCapabilityAdapter(): XGatewayReadCapabilityAdapter {
    const client = createBearerRestClient();
    const postGet = async (
      options: XGatewayPostGetOptions,
    ): Promise<XGatewayPostLookupResult> => {
      const postId = dependencies.ensureRequired(options.postId, "postId");
      const response = await client.v2.singleTweet(postId, POST_LOOKUP_FIELDS);
      return mapPostLookupResult(response);
    };
    const likesList = async (
      options: XGatewayLikesListOptions,
    ): Promise<XGatewayLikesListResult> => {
      const userId = dependencies.ensureRequired(options.userId, "userId");
      const limit = validateLikesListLimit(
        options.limit,
        dependencies.createValidationError,
      );
      const response = await client.v2.userLikedTweets(userId, {
        ...POST_LOOKUP_FIELDS,
        ...(limit === undefined ? {} : { max_results: limit }),
      });
      return mapLikesListResult(userId, response.tweets, response.includes);
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
      likesList,
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

    return {
      adapterKind: "rest-oauth1",
      postCreate: async (options: XGatewayPostCreateOptions) => {
        const text = dependencies.ensureRequired(options.text, "text");
        return client.v2.tweet(text);
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
        return client.v2.reply(text, replyToPostId);
      },
      postQuote: async (options: XGatewayPostQuoteOptions) => {
        const text = dependencies.ensureRequired(options.text, "text");
        const quotedPostId = dependencies.ensureRequired(
          options.quotedPostId,
          "quotedPostId",
        );
        return client.v2.quote(text, quotedPostId);
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
