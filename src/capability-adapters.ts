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
  XGatewayUsageClientApp,
  XGatewayUsageDay,
  XGatewayUsageProjectTimeline,
  XGatewayUsageTweetsOptions,
  XGatewayUsageTweetsResult,
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

type UsageApiUsageEntryPayload = Readonly<{
  date?: unknown;
  usage?: unknown;
}>;

type UsageApiClientAppPayload = Readonly<{
  client_app_id?: unknown;
  usage?: unknown;
  usage_result_count?: unknown;
}>;

type UsageApiProjectPayload = Readonly<{
  project_id?: unknown;
  usage?: unknown;
}>;

type UsageApiDataPayload = Readonly<{
  cap_reset_day?: unknown;
  daily_client_app_usage?: unknown;
  daily_project_usage?: unknown;
  project_cap?: unknown;
  project_id?: unknown;
  project_usage?: unknown;
}>;

type UsageApiErrorPayload = Readonly<{
  title?: unknown;
  detail?: unknown;
  type?: unknown;
  status?: unknown;
}>;

type UsageApiResponsePayload = Readonly<{
  data?: unknown;
  errors?: unknown;
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

function normalizeRequiredInput(
  value: string | undefined,
  fieldName: string,
  ensureRequired: (value: string | undefined, fieldName: string) => string,
): string {
  return ensureRequired(value, fieldName).trim();
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

function parseRetryAfterMs(headerValue: string | null): number | undefined {
  if (headerValue === null || !isNonEmpty(headerValue)) {
    return undefined;
  }

  const seconds = Number(headerValue);
  if (Number.isFinite(seconds) && seconds >= 0) {
    return Math.floor(seconds * 1000);
  }

  const retryAt = Date.parse(headerValue);
  if (!Number.isFinite(retryAt)) {
    return undefined;
  }

  return Math.max(retryAt - Date.now(), 0);
}

async function parseResponseBody(response: Response): Promise<unknown> {
  const contentType = response.headers.get("content-type") ?? "";
  if (
    contentType.includes("application/json") ||
    contentType.includes("+json")
  ) {
    return (await response.json()) as unknown;
  }
  return {
    raw: await response.text(),
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
  function createUsagePayloadError(detail: string): XGatewayError {
    return dependencies.createError({
      code: "UPSTREAM_FAILURE",
      summary: "Usage endpoint returned an unexpected payload",
      details: detail,
      likelyCauses: [
        "The upstream usage endpoint returned a schema different from the reviewed baseline",
        "The account lacks access to the expected usage response shape",
      ],
      remediations: [
        "Inspect the upstream usage response and update the reviewed mapper if the X API contract changed.",
        "Confirm the bearer token and project still have access to usage metrics.",
      ],
      classification: "upstream",
      retryable: false,
    });
  }

  function readUsageInteger(value: unknown, fieldName: string): number {
    if (
      typeof value === "number" &&
      Number.isInteger(value) &&
      Number.isFinite(value) &&
      value >= 0
    ) {
      return value;
    }
    throw createUsagePayloadError(
      `Field '${fieldName}' must be a non-negative integer in the usage response.`,
    );
  }

  function readUsageString(value: unknown, fieldName: string): string {
    if (typeof value === "string" && value.trim().length > 0) {
      return value;
    }
    throw createUsagePayloadError(
      `Field '${fieldName}' must be a non-empty string in the usage response.`,
    );
  }

  function readUsageEntry(value: unknown, fieldName: string): XGatewayUsageDay {
    if (typeof value !== "object" || value === null) {
      throw createUsagePayloadError(
        `Field '${fieldName}' must contain usage entry objects.`,
      );
    }
    const entry = value as UsageApiUsageEntryPayload;
    return {
      date: readUsageString(entry.date, `${fieldName}.date`),
      usage: readUsageInteger(entry.usage, `${fieldName}.usage`),
    };
  }

  function readUsageEntryArray(
    value: unknown,
    fieldName: string,
  ): readonly XGatewayUsageDay[] {
    if (!Array.isArray(value)) {
      throw createUsagePayloadError(
        `Field '${fieldName}' must be an array in the usage response.`,
      );
    }
    return value.map((entry, index) =>
      readUsageEntry(entry, `${fieldName}[${index}]`),
    );
  }

  function readUsageClientApp(
    value: unknown,
    fieldName: string,
  ): XGatewayUsageClientApp {
    if (typeof value !== "object" || value === null) {
      throw createUsagePayloadError(
        `Field '${fieldName}' must contain client-app usage objects.`,
      );
    }
    const clientApp = value as UsageApiClientAppPayload;
    return {
      clientAppId: readUsageString(
        clientApp.client_app_id,
        `${fieldName}.client_app_id`,
      ),
      usage: readUsageEntryArray(clientApp.usage, `${fieldName}.usage`),
      usageResultCount: readUsageInteger(
        clientApp.usage_result_count,
        `${fieldName}.usage_result_count`,
      ),
    };
  }

  function readUsageClientAppArray(
    value: unknown,
    fieldName: string,
  ): readonly XGatewayUsageClientApp[] {
    if (!Array.isArray(value)) {
      throw createUsagePayloadError(
        `Field '${fieldName}' must be an array in the usage response.`,
      );
    }
    return value.map((entry, index) =>
      readUsageClientApp(entry, `${fieldName}[${index}]`),
    );
  }

  function readUsageProjectTimeline(
    value: unknown,
    fieldName: string,
  ): XGatewayUsageProjectTimeline {
    if (typeof value !== "object" || value === null) {
      throw createUsagePayloadError(
        `Field '${fieldName}' must be an object in the usage response.`,
      );
    }
    const projectTimeline = value as UsageApiProjectPayload;
    return {
      projectId: readUsageString(
        projectTimeline.project_id,
        `${fieldName}.project_id`,
      ),
      usage: readUsageEntryArray(projectTimeline.usage, `${fieldName}.usage`),
    };
  }

  function mapUsageTweetsPayload(payload: unknown): XGatewayUsageTweetsResult {
    if (typeof payload !== "object" || payload === null) {
      throw createUsagePayloadError(
        "The usage endpoint did not return an object payload.",
      );
    }
    const data = payload as UsageApiDataPayload;
    return {
      capResetDay: readUsageInteger(data.cap_reset_day, "cap_reset_day"),
      dailyClientAppUsage: readUsageClientAppArray(
        data.daily_client_app_usage,
        "daily_client_app_usage",
      ),
      dailyProjectUsage: readUsageProjectTimeline(
        data.daily_project_usage,
        "daily_project_usage",
      ),
      projectCap: readUsageInteger(data.project_cap, "project_cap"),
      projectId: readUsageString(data.project_id, "project_id"),
      projectUsage: readUsageInteger(data.project_usage, "project_usage"),
    };
  }

  function validateUsageDays(
    value: number | undefined,
    fieldName: string,
  ): number | undefined {
    if (value === undefined) {
      return undefined;
    }
    if (!Number.isInteger(value) || value < 1 || value > 90) {
      throw dependencies.createValidationError(
        `${fieldName} must be an integer between 1 and 90.`,
      );
    }
    return value;
  }

  function readUsageApiProblemDetail(payload: unknown): string | undefined {
    if (typeof payload !== "object" || payload === null) {
      return undefined;
    }
    const responsePayload = payload as UsageApiResponsePayload;
    if (
      !Array.isArray(responsePayload.errors) ||
      responsePayload.errors.length === 0
    ) {
      return undefined;
    }
    const [firstError] =
      responsePayload.errors as readonly UsageApiErrorPayload[];
    if (typeof firstError !== "object" || firstError === null) {
      return undefined;
    }
    const title =
      typeof firstError.title === "string"
        ? firstError.title
        : "Usage request failed";
    const detail =
      typeof firstError.detail === "string" ? firstError.detail : undefined;
    const status =
      typeof firstError.status === "number"
        ? String(firstError.status)
        : undefined;
    return [
      title,
      detail,
      status === undefined ? undefined : `status=${status}`,
    ]
      .filter((part): part is string => part !== undefined && part.length > 0)
      .join(": ");
  }

  async function fetchUsageTweets(
    options: XGatewayUsageTweetsOptions,
  ): Promise<XGatewayUsageTweetsResult> {
    const days = validateUsageDays(options.days, "days");
    if (!hasBearerToken(dependencies.auth)) {
      throw dependencies.createError({
        code: "AUTH_MISSING",
        summary: "Authentication configuration missing",
        details:
          "The reviewed usage endpoint adapter requires X_GW_TOKEN or auth.token.",
        likelyCauses: [
          "Bearer token was not configured",
          "Only OAuth1 credentials were provided",
        ],
        remediations: ["Set X_GW_TOKEN for bearer-token usage."],
        classification: "auth",
        retryable: false,
      });
    }

    const query = new URLSearchParams();
    if (days !== undefined) {
      query.set("days", String(days));
    }
    const endpoint = `https://api.x.com/2/usage/tweets${
      query.size === 0 ? "" : `?${query.toString()}`
    }`;
    const response = await fetch(endpoint, {
      method: "GET",
      headers: {
        authorization: `Bearer ${dependencies.auth.token!}`,
        accept: "application/json",
      },
    });
    const payload = await parseResponseBody(response);

    if (!response.ok) {
      const retryAfterMs = parseRetryAfterMs(
        response.headers.get("retry-after"),
      );
      const detail =
        readUsageApiProblemDetail(payload) ??
        (typeof payload === "object" && payload !== null
          ? JSON.stringify(payload)
          : String(payload));
      throw dependencies.createError({
        code:
          response.status === 401
            ? "AUTH_INVALID"
            : response.status === 403
              ? "PERMISSION_DENIED"
              : response.status === 404
                ? "RESOURCE_NOT_FOUND"
                : response.status === 429
                  ? "RATE_LIMITED"
                  : "UPSTREAM_FAILURE",
        summary: "Usage request failed",
        details: `HTTP ${response.status} returned from GET /2/usage/tweets. Response body: ${detail}`,
        likelyCauses: [
          "Bearer token is invalid or lacks access to usage metrics",
          "The project does not have access to the usage endpoint for the selected environment",
          "The upstream usage endpoint returned an error payload",
        ],
        remediations: [
          "Confirm the bearer token is valid and attached to the expected X project.",
          "Retry with a supported bearer token after verifying project usage access in the Developer Console.",
          "If the problem persists, inspect the upstream response body for tier-specific access limits.",
        ],
        classification:
          response.status === 401
            ? "auth"
            : response.status === 403
              ? "permission"
              : response.status === 429
                ? "rate_limit"
                : "upstream",
        retryable: response.status === 429 || response.status >= 500,
        httpStatus: response.status,
        ...(retryAfterMs === undefined ? {} : { retryAfterMs }),
      });
    }

    const responsePayload =
      typeof payload === "object" && payload !== null
        ? (payload as UsageApiResponsePayload)
        : undefined;
    if (responsePayload?.data === undefined) {
      throw createUsagePayloadError(
        "The usage endpoint returned a successful HTTP response without a 'data' object.",
      );
    }

    return mapUsageTweetsPayload(responsePayload.data);
  }

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
      const maxResults = validateOptionalMaxResults(
        options.maxResults,
        "maxResults",
        5,
        100,
        dependencies.createValidationError,
      );
      const paginationToken = validateOptionalPaginationToken(
        options.paginationToken,
        "paginationToken",
        dependencies.createValidationError,
      );
      const response = await client.v2.homeTimeline({
        ...(maxResults === undefined ? {} : { max_results: maxResults }),
        ...(paginationToken === undefined
          ? {}
          : { pagination_token: paginationToken }),
        ...POST_LOOKUP_FIELDS,
      });
      return mapPostPage(response.data as V2TimelinePayload);
    };
    const timelineUser = async (
      options: XGatewayTimelineUserOptions,
    ): Promise<XGatewayPostPage> => {
      const userId = normalizeRequiredInput(
        options.userId,
        "userId",
        dependencies.ensureRequired,
      );
      const maxResults = validateOptionalMaxResults(
        options.maxResults,
        "maxResults",
        5,
        100,
        dependencies.createValidationError,
      );
      const paginationToken = validateOptionalPaginationToken(
        options.paginationToken,
        "paginationToken",
        dependencies.createValidationError,
      );
      const response = await client.v2.userTimeline(userId, {
        ...(maxResults === undefined ? {} : { max_results: maxResults }),
        ...(paginationToken === undefined
          ? {}
          : { pagination_token: paginationToken }),
        ...POST_LOOKUP_FIELDS,
      });
      return mapPostPage(response.data as V2TimelinePayload);
    };
    const timelineMentions = async (
      options: XGatewayTimelineUserOptions,
    ): Promise<XGatewayPostPage> => {
      const userId = normalizeRequiredInput(
        options.userId,
        "userId",
        dependencies.ensureRequired,
      );
      const maxResults = validateOptionalMaxResults(
        options.maxResults,
        "maxResults",
        5,
        100,
        dependencies.createValidationError,
      );
      const paginationToken = validateOptionalPaginationToken(
        options.paginationToken,
        "paginationToken",
        dependencies.createValidationError,
      );
      const response = await client.v2.userMentionTimeline(userId, {
        ...(maxResults === undefined ? {} : { max_results: maxResults }),
        ...(paginationToken === undefined
          ? {}
          : { pagination_token: paginationToken }),
        ...POST_LOOKUP_FIELDS,
      });
      return mapPostPage(response.data as V2TimelinePayload);
    };
    const timelineSearch = async (
      options: XGatewayTimelineSearchOptions,
    ): Promise<XGatewayPostPage> => {
      const query = normalizeRequiredInput(
        options.query,
        "query",
        dependencies.ensureRequired,
      );
      const maxResults = validateOptionalMaxResults(
        options.maxResults,
        "maxResults",
        10,
        100,
        dependencies.createValidationError,
      );
      const paginationToken = validateOptionalPaginationToken(
        options.paginationToken,
        "paginationToken",
        dependencies.createValidationError,
      );
      const response = await client.v2.search(query, {
        ...(maxResults === undefined ? {} : { max_results: maxResults }),
        ...(paginationToken === undefined
          ? {}
          : { next_token: paginationToken }),
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
      usageTweets: async () => {
        throw dependencies.createError({
          code: "UNSUPPORTED",
          summary: "Post usage statistics require bearer auth",
          details:
            "The reviewed usage endpoint adapter uses bearer authentication only. OAuth1 credentials are not sufficient for GET /2/usage/tweets in the current stable surface.",
          likelyCauses: [
            "Only OAuth1 credentials were configured",
            "The usage endpoint was invoked through an unsupported auth family",
          ],
          remediations: [
            "Configure X_GW_TOKEN or auth.token for bearer-backed usage inspection.",
          ],
          classification: "unsupported",
          retryable: false,
        });
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
      const maxResults = validateOptionalMaxResults(
        options.maxResults,
        "maxResults",
        5,
        100,
        dependencies.createValidationError,
      );
      const paginationToken = validateOptionalPaginationToken(
        options.paginationToken,
        "paginationToken",
        dependencies.createValidationError,
      );
      const response = await client.v2.homeTimeline({
        ...(maxResults === undefined ? {} : { max_results: maxResults }),
        ...(paginationToken === undefined
          ? {}
          : { pagination_token: paginationToken }),
        ...POST_LOOKUP_FIELDS,
      });
      return mapPostPage(response.data as V2TimelinePayload);
    };
    const timelineUser = async (
      options: XGatewayTimelineUserOptions,
    ): Promise<XGatewayPostPage> => {
      const userId = normalizeRequiredInput(
        options.userId,
        "userId",
        dependencies.ensureRequired,
      );
      const maxResults = validateOptionalMaxResults(
        options.maxResults,
        "maxResults",
        5,
        100,
        dependencies.createValidationError,
      );
      const paginationToken = validateOptionalPaginationToken(
        options.paginationToken,
        "paginationToken",
        dependencies.createValidationError,
      );
      const response = await client.v2.userTimeline(userId, {
        ...(maxResults === undefined ? {} : { max_results: maxResults }),
        ...(paginationToken === undefined
          ? {}
          : { pagination_token: paginationToken }),
        ...POST_LOOKUP_FIELDS,
      });
      return mapPostPage(response.data as V2TimelinePayload);
    };
    const timelineMentions = async (
      options: XGatewayTimelineUserOptions,
    ): Promise<XGatewayPostPage> => {
      const userId = normalizeRequiredInput(
        options.userId,
        "userId",
        dependencies.ensureRequired,
      );
      const maxResults = validateOptionalMaxResults(
        options.maxResults,
        "maxResults",
        5,
        100,
        dependencies.createValidationError,
      );
      const paginationToken = validateOptionalPaginationToken(
        options.paginationToken,
        "paginationToken",
        dependencies.createValidationError,
      );
      const response = await client.v2.userMentionTimeline(userId, {
        ...(maxResults === undefined ? {} : { max_results: maxResults }),
        ...(paginationToken === undefined
          ? {}
          : { pagination_token: paginationToken }),
        ...POST_LOOKUP_FIELDS,
      });
      return mapPostPage(response.data as V2TimelinePayload);
    };
    const timelineSearch = async (
      options: XGatewayTimelineSearchOptions,
    ): Promise<XGatewayPostPage> => {
      const query = normalizeRequiredInput(
        options.query,
        "query",
        dependencies.ensureRequired,
      );
      const maxResults = validateOptionalMaxResults(
        options.maxResults,
        "maxResults",
        10,
        100,
        dependencies.createValidationError,
      );
      const paginationToken = validateOptionalPaginationToken(
        options.paginationToken,
        "paginationToken",
        dependencies.createValidationError,
      );
      const response = await client.v2.search(query, {
        ...(maxResults === undefined ? {} : { max_results: maxResults }),
        ...(paginationToken === undefined
          ? {}
          : { next_token: paginationToken }),
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
      usageTweets: fetchUsageTweets,
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
