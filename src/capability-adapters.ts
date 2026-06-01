import { mkdir, stat, writeFile } from "node:fs/promises";
import { basename, extname, join, resolve } from "node:path";
import {
  TwitterApi,
  TwitterV2IncludesHelper,
  type MediaObjectV2,
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
  XGatewayMediaAsset,
  XGatewayPostAttachmentInput,
  XGatewayPostPage,
  XGatewayPostCreateOptions,
  XGatewayPostDeleteOptions,
  XGatewayPostGetOptions,
  XGatewayPostLookupResult,
  XGatewayPostMetrics,
  XGatewayPromotionStatus,
  XGatewayPostQuoteOptions,
  XGatewayPostRepliesOptions,
  XGatewayPostReferenceRelation,
  XGatewayPostReplyOptions,
  XGatewayPostRepostOptions,
  XGatewayReferencedPost,
  XGatewayPostSummary,
  XGatewayFollowingTimelineOptions,
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
    "attachments.media_keys",
    "referenced_tweets.id",
    "referenced_tweets.id.author_id",
    "referenced_tweets.id.attachments.media_keys",
  ],
  "media.fields": [
    "alt_text",
    "duration_ms",
    "height",
    "media_key",
    "preview_image_url",
    "type",
    "url",
    "variants",
    "width",
  ],
  "tweet.fields": [
    "attachments",
    "author_id",
    "conversation_id",
    "created_at",
    "in_reply_to_user_id",
    "organic_metrics",
    "public_metrics",
    "promoted_metrics",
    "referenced_tweets",
  ],
  "user.fields": ["id", "name", "username"],
} as const;
const MAX_TWEET_LOOKUP_IDS = 100;

type CapabilityAdapterDependencies = Readonly<{
  auth: XGatewayAuthConfig;
  mediaRootDir?: string;
  createError: (payload: XGatewayErrorPayload) => XGatewayError;
  createValidationError: (message: string) => XGatewayError;
  ensureRequired: (value: string | undefined, fieldName: string) => string;
}>;

type V2TweetLookupPayload = Readonly<{
  data?: readonly TweetV2[];
  includes?: Readonly<{
    media?: readonly MediaObjectV2[];
    tweets?: readonly TweetV2[];
    users?: readonly UserV2[];
  }>;
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
    media?: readonly MediaObjectV2[];
    tweets?: readonly TweetV2[];
    users?: readonly UserV2[];
  }>;
  meta?: V2TimelineMeta;
}>;

type V2UserTimelinePayload = Readonly<{
  data?: readonly UserV2[];
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

type ExpandedTweetContext = Readonly<{
  includesHelper: TwitterV2IncludesHelper;
}>;

type PostReadOptions = Readonly<{
  mediaRootDir?: string;
  downloadMedia: boolean;
  forceDownload: boolean;
  includePromoted: boolean;
}>;

type PostPageRequestInputs = Readonly<{
  postReadOptions: PostReadOptions;
  maxResults?: number;
  paginationToken?: string;
}>;

type RestTimelineRequestOptions = Partial<Tweetv2FieldsParams> &
  Readonly<{
    max_results?: number;
    pagination_token?: string;
    next_token?: string;
  }>;

type FollowingTimelineRequestInputs = Readonly<{
  postReadOptions: PostReadOptions;
  maxResults: number;
  maxUsers: number;
  maxResultsPerUser: number;
}>;

type RestPaginationTokenField = "pagination_token" | "next_token";

type TweetMetricShape = Readonly<Record<string, unknown>>;
type TweetMetricFieldName =
  | "public_metrics"
  | "organic_metrics"
  | "promoted_metrics";

function isObjectRecord(
  value: unknown,
): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasFiniteMetricValue(metrics: TweetMetricShape): boolean {
  return Object.values(metrics).some(
    (value) => typeof value === "number" && Number.isFinite(value),
  );
}

function readTweetMetrics(
  tweet: TweetV2,
  fieldName: TweetMetricFieldName,
): TweetMetricShape | undefined {
  const value = (tweet as TweetV2 & Readonly<Record<string, unknown>>)[
    fieldName
  ];
  return isObjectRecord(value) ? value : undefined;
}

function readNullableMetricNumber(
  metrics: TweetMetricShape | undefined,
  metricName: string,
): number | null {
  const value = metrics?.[metricName];
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function readFirstAvailableMetricNumber(
  tweet: TweetV2,
  fieldNames: readonly TweetMetricFieldName[],
  metricName: string,
): number | null {
  for (const fieldName of fieldNames) {
    const value = readNullableMetricNumber(
      readTweetMetrics(tweet, fieldName),
      metricName,
    );
    if (value !== null) {
      return value;
    }
  }
  return null;
}

function mapPostMetrics(tweet: TweetV2): XGatewayPostMetrics {
  return {
    likeCount: readFirstAvailableMetricNumber(
      tweet,
      ["public_metrics"],
      "like_count",
    ),
    replyCount: readFirstAvailableMetricNumber(
      tweet,
      ["public_metrics"],
      "reply_count",
    ),
    repostCount: readFirstAvailableMetricNumber(
      tweet,
      ["public_metrics"],
      "retweet_count",
    ),
    quoteCount: readFirstAvailableMetricNumber(
      tweet,
      ["public_metrics"],
      "quote_count",
    ),
    bookmarkCount: readFirstAvailableMetricNumber(
      tweet,
      ["public_metrics"],
      "bookmark_count",
    ),
    impressionCount: readFirstAvailableMetricNumber(
      tweet,
      ["public_metrics", "organic_metrics", "promoted_metrics"],
      "impression_count",
    ),
  };
}

function detectPromotionStatus(tweet: TweetV2): XGatewayPromotionStatus {
  const promotedMetrics = readTweetMetrics(tweet, "promoted_metrics");
  if (promotedMetrics && hasFiniteMetricValue(promotedMetrics)) {
    return "PROMOTED";
  }

  const organicMetrics = readTweetMetrics(tweet, "organic_metrics");
  if (organicMetrics && hasFiniteMetricValue(organicMetrics)) {
    return "NOT_PROMOTED";
  }

  return "UNKNOWN";
}

function collectReferencedTweetIds(
  tweets: readonly TweetV2[],
): readonly string[] {
  const referencedTweetIds = new Set<string>();

  for (const tweet of tweets) {
    for (const reference of tweet.referenced_tweets ?? []) {
      if (isSupportedPostReferenceRelation(reference.type)) {
        referencedTweetIds.add(reference.id);
      }
    }
  }

  return [...referencedTweetIds];
}

async function fetchReferencedTweetPayloads(
  client: TwitterApi,
  tweets: readonly TweetV2[],
): Promise<readonly V2TweetLookupPayload[]> {
  const referencedTweetIds = collectReferencedTweetIds(tweets);
  if (referencedTweetIds.length === 0) {
    return [];
  }

  const payloads: V2TweetLookupPayload[] = [];
  for (
    let startIndex = 0;
    startIndex < referencedTweetIds.length;
    startIndex += MAX_TWEET_LOOKUP_IDS
  ) {
    const tweetIds = referencedTweetIds.slice(
      startIndex,
      startIndex + MAX_TWEET_LOOKUP_IDS,
    );
    const payload = await client.v2.tweets(tweetIds, POST_LOOKUP_FIELDS);
    payloads.push(payload as V2TweetLookupPayload);
  }
  return payloads;
}

function buildIncludesHelper(
  payloads: readonly V2TweetLookupPayload[],
): ExpandedTweetContext {
  const tweetsById = new Map<string, TweetV2>();
  const mediaByKey = new Map<string, MediaObjectV2>();
  const usersById = new Map<string, UserV2>();

  for (const payload of payloads) {
    for (const tweet of payload.data ?? []) {
      tweetsById.set(tweet.id, tweet);
    }
    for (const tweet of payload.includes?.tweets ?? []) {
      tweetsById.set(tweet.id, tweet);
    }
    for (const media of payload.includes?.media ?? []) {
      mediaByKey.set(media.media_key, media);
    }
    for (const user of payload.includes?.users ?? []) {
      usersById.set(user.id, user);
    }
  }

  return {
    includesHelper: new TwitterV2IncludesHelper({
      includes: {
        ...(mediaByKey.size === 0 ? {} : { media: [...mediaByKey.values()] }),
        ...(tweetsById.size === 0 ? {} : { tweets: [...tweetsById.values()] }),
        ...(usersById.size === 0 ? {} : { users: [...usersById.values()] }),
      },
    }),
  };
}

async function createNestedReferenceIncludesHelper(
  client: TwitterApi,
  payload: V2TweetLookupPayload,
): Promise<ExpandedTweetContext> {
  const nestedReferencePayloads = await fetchReferencedTweetPayloads(
    client,
    payload.data ?? [],
  );
  return buildIncludesHelper([payload, ...nestedReferencePayloads]);
}

function sanitizePathComponent(input: string): string {
  const sanitized = input.replace(/[^A-Za-z0-9._-]+/g, "_");
  return sanitized.length === 0 ? "media" : sanitized;
}

function inferExtensionFromContentType(contentType: string): string {
  if (contentType === "image/jpeg") {
    return ".jpg";
  }
  if (contentType === "image/png") {
    return ".png";
  }
  if (contentType === "image/gif") {
    return ".gif";
  }
  if (contentType === "video/mp4") {
    return ".mp4";
  }
  if (contentType === "application/x-mpegURL") {
    return ".m3u8";
  }
  return "";
}

function buildMediaFileName(
  mediaKey: string,
  sourceUrl: string,
  contentType: string,
): string {
  const sourcePath = new URL(sourceUrl).pathname;
  const originalBaseName = basename(sourcePath);
  const sanitizedBaseName =
    originalBaseName.length > 0
      ? sanitizePathComponent(originalBaseName)
      : sanitizePathComponent(mediaKey);

  if (extname(sanitizedBaseName).length > 0) {
    return sanitizedBaseName;
  }

  const inferredExtension = inferExtensionFromContentType(contentType);
  return inferredExtension.length === 0
    ? sanitizedBaseName
    : `${sanitizedBaseName}${inferredExtension}`;
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    await stat(filePath);
    return true;
  } catch (error) {
    const code =
      typeof error === "object" &&
      error !== null &&
      "code" in error &&
      typeof error.code === "string"
        ? error.code
        : undefined;
    if (code === "ENOENT") {
      return false;
    }
    throw error;
  }
}

function pickMediaSource(
  media: MediaObjectV2,
): Readonly<{ contentType: string; sourceUrl: string }> | undefined {
  if (media.type === "photo" && isNonEmpty(media.url)) {
    const extension = extname(new URL(media.url).pathname).toLowerCase();
    return {
      contentType: extension === ".png" ? "image/png" : "image/jpeg",
      sourceUrl: media.url,
    };
  }

  const mp4Variant = [...(media.variants ?? [])]
    .filter((variant) => variant.content_type === "video/mp4")
    .sort((left, right) => (right.bit_rate ?? 0) - (left.bit_rate ?? 0))[0];
  if (mp4Variant && isNonEmpty(mp4Variant.url)) {
    return {
      contentType: mp4Variant.content_type,
      sourceUrl: mp4Variant.url,
    };
  }

  return undefined;
}

async function materializeMediaAsset(
  media: MediaObjectV2,
  postId: string,
  options: PostReadOptions,
): Promise<XGatewayMediaAsset | undefined> {
  const source = pickMediaSource(media);
  if (!source) {
    return undefined;
  }

  const previewImageUrl = isNonEmpty(media.preview_image_url)
    ? media.preview_image_url
    : undefined;
  const asset: XGatewayMediaAsset = {
    kind:
      media.type === "photo" ||
      media.type === "video" ||
      media.type === "animated_gif"
        ? media.type
        : "photo",
    contentType: source.contentType,
    sourceUrl: source.sourceUrl,
    ...(previewImageUrl === undefined ? {} : { previewImageUrl }),
  };

  if (!options.downloadMedia || options.mediaRootDir === undefined) {
    return asset;
  }

  const fileName = buildMediaFileName(
    media.media_key,
    source.sourceUrl,
    source.contentType,
  );
  const postDir = resolve(options.mediaRootDir, sanitizePathComponent(postId));
  const localFilePath = join(postDir, fileName);
  if (!options.forceDownload && (await fileExists(localFilePath))) {
    return {
      ...asset,
      localFilePath,
    };
  }
  const response = await fetch(source.sourceUrl);
  if (!response.ok) {
    throw new Error(
      `Media download failed for ${source.sourceUrl} with HTTP ${response.status}.`,
    );
  }
  await mkdir(postDir, { recursive: true });
  await writeFile(localFilePath, new Uint8Array(await response.arrayBuffer()));
  return {
    ...asset,
    localFilePath,
  };
}

async function mapMediaAssets(
  tweet: TweetV2,
  context: ExpandedTweetContext,
  options: PostReadOptions,
): Promise<readonly XGatewayMediaAsset[]> {
  const mediaItems = context.includesHelper.medias(tweet);
  const assets = await Promise.all(
    mediaItems.map((media) => materializeMediaAsset(media, tweet.id, options)),
  );
  return assets.filter(
    (asset): asset is XGatewayMediaAsset => asset !== undefined,
  );
}

async function mapPostSummary(
  tweet: TweetV2,
  context: ExpandedTweetContext,
  postReadOptions: PostReadOptions,
  maxReferenceDepth = 0,
): Promise<XGatewayPostSummary | undefined> {
  const promotionStatus = detectPromotionStatus(tweet);
  if (!postReadOptions.includePromoted && promotionStatus === "PROMOTED") {
    return undefined;
  }

  const author = mapOptionalAccountProfile(
    context.includesHelper.author(tweet),
  );
  const [media, referencedPosts] = await Promise.all([
    mapMediaAssets(tweet, context, postReadOptions),
    maxReferenceDepth > 0
      ? mapReferencedPosts(tweet, context, postReadOptions, maxReferenceDepth)
      : Promise.resolve([] as XGatewayReferencedPost[]),
  ]);
  const replyTo = referencedPosts.find(
    (referencedPost) => referencedPost.relation === "replied_to",
  );
  const quote = referencedPosts.find(
    (referencedPost) => referencedPost.relation === "quoted",
  );
  const repost = referencedPosts.find(
    (referencedPost) => referencedPost.relation === "retweeted",
  );
  return {
    id: tweet.id,
    text: tweet.text,
    promotionStatus,
    metrics: mapPostMetrics(tweet),
    ...(tweet.created_at === undefined ? {} : { createdAt: tweet.created_at }),
    ...(tweet.conversation_id === undefined
      ? {}
      : { conversationId: tweet.conversation_id }),
    ...(tweet.in_reply_to_user_id === undefined
      ? {}
      : { replyToUserId: tweet.in_reply_to_user_id }),
    ...(author === undefined ? {} : { author }),
    ...(media.length === 0 ? {} : { media }),
    ...(replyTo === undefined ? {} : { replyTo }),
    ...(quote === undefined ? {} : { quote }),
    ...(repost === undefined ? {} : { repost }),
    ...(referencedPosts.length === 0 ? {} : { referencedPosts }),
  };
}

async function mapReferencedPosts(
  tweet: TweetV2,
  context: ExpandedTweetContext,
  postReadOptions: PostReadOptions,
  maxReferenceDepth: number,
): Promise<XGatewayReferencedPost[]> {
  const references = tweet.referenced_tweets ?? [];
  const referencedPosts = await Promise.all(
    references.map(async (reference) => {
      if (!isSupportedPostReferenceRelation(reference.type)) {
        return undefined;
      }
      const referencedTweet = context.includesHelper.tweetById(reference.id);
      if (!referencedTweet) {
        return undefined;
      }
      const referencedPost = await mapPostSummary(
        referencedTweet,
        context,
        postReadOptions,
        maxReferenceDepth - 1,
      );
      if (!referencedPost) {
        return undefined;
      }
      return {
        relation: reference.type,
        ...referencedPost,
      };
    }),
  );
  return referencedPosts.filter(
    (referencedPost): referencedPost is XGatewayReferencedPost =>
      referencedPost !== undefined,
  );
}

async function mapPostLookupResult(
  client: TwitterApi,
  response: TweetV2SingleResult,
  postReadOptions: PostReadOptions,
  createError: (payload: XGatewayErrorPayload) => XGatewayError,
): Promise<XGatewayPostLookupResult> {
  const context = await createNestedReferenceIncludesHelper(client, {
    data: [response.data],
    ...(response.includes === undefined ? {} : { includes: response.includes }),
  });
  const post = await mapPostSummary(response.data, context, postReadOptions, 2);
  if (!post) {
    throw createError({
      code: "PERMISSION_DENIED",
      summary: "Promoted post filtered from the stable read surface",
      details:
        "The requested post was identified as promoted in the upstream payload and x-gateway excluded it because includePromoted was not enabled.",
      likelyCauses: [
        "The post is currently promoted for the authenticated author context",
        "The request relied on the default includePromoted: false behavior",
      ],
      remediations: [
        "Retry with includePromoted: true if you want promoted posts returned.",
      ],
      classification: "permission",
      retryable: false,
    });
  }

  return {
    post,
    referencedPosts: post.referencedPosts ?? [],
  };
}

async function mapPostPage(
  client: TwitterApi,
  response: V2TimelinePayload,
  postReadOptions: PostReadOptions,
): Promise<XGatewayPostPage> {
  const tweets = response.data ?? [];
  const context = await createNestedReferenceIncludesHelper(client, response);
  const meta = response.meta;
  const posts = (
    await Promise.all(
      tweets.map((tweet) => mapPostSummary(tweet, context, postReadOptions, 2)),
    )
  ).filter((post): post is XGatewayPostSummary => post !== undefined);
  const oldestPost = posts.length === 0 ? undefined : posts[posts.length - 1];
  return {
    posts,
    pageInfo: {
      resultCount: posts.length,
      ...(meta?.next_token === undefined ? {} : { nextToken: meta.next_token }),
      ...(meta?.previous_token === undefined
        ? {}
        : { previousToken: meta.previous_token }),
      ...(posts[0]?.id === undefined
        ? meta?.newest_id === undefined
          ? {}
          : { newestId: meta.newest_id }
        : { newestId: posts[0].id }),
      ...(oldestPost?.id === undefined
        ? meta?.oldest_id === undefined
          ? {}
          : { oldestId: meta.oldest_id }
        : { oldestId: oldestPost.id }),
    },
  };
}

function createPostPageFromMergedPosts(
  posts: readonly XGatewayPostSummary[],
): XGatewayPostPage {
  const oldestPost = posts.length === 0 ? undefined : posts[posts.length - 1];
  return {
    posts,
    pageInfo: {
      resultCount: posts.length,
      ...(posts[0]?.id === undefined ? {} : { newestId: posts[0].id }),
      ...(oldestPost?.id === undefined ? {} : { oldestId: oldestPost.id }),
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

function validateSearchOperatorToken(
  value: string,
  fieldName: string,
  createValidationError: (message: string) => XGatewayError,
): string {
  if (/\s/.test(value)) {
    throw createValidationError(
      `${fieldName} must be a single token without whitespace.`,
    );
  }
  if (!/^[A-Za-z0-9_:-]+$/.test(value)) {
    throw createValidationError(
      `${fieldName} contains unsupported characters for reply lookup search.`,
    );
  }
  return value;
}

function buildPostRepliesSearchQuery(
  options: XGatewayPostRepliesOptions,
  dependencies: CapabilityAdapterDependencies,
): string {
  const postId = validateSearchOperatorToken(
    normalizeRequiredInput(
      options.postId,
      "postId",
      dependencies.ensureRequired,
    ),
    "postId",
    dependencies.createValidationError,
  );
  return `in_reply_to_tweet_id:${postId}`;
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

function readPostReadOptions(
  options: Readonly<{
    mediaRootDir?: string;
    downloadMedia?: boolean;
    forceDownload?: boolean;
    includePromoted?: boolean;
  }>,
  dependencies: CapabilityAdapterDependencies,
): PostReadOptions {
  const mediaRootDir =
    options.mediaRootDir === undefined
      ? dependencies.mediaRootDir
      : options.mediaRootDir.trim().length === 0
        ? undefined
        : options.mediaRootDir.trim();
  return {
    ...(mediaRootDir === undefined ? {} : { mediaRootDir }),
    downloadMedia: options.downloadMedia ?? true,
    forceDownload: options.forceDownload ?? false,
    includePromoted: options.includePromoted ?? false,
  };
}

function readPostPageRequestInputs(
  options: Readonly<{
    mediaRootDir?: string;
    downloadMedia?: boolean;
    forceDownload?: boolean;
    includePromoted?: boolean;
    maxResults?: number;
    paginationToken?: string;
  }>,
  minimumMaxResults: number,
  dependencies: CapabilityAdapterDependencies,
): PostPageRequestInputs {
  const maxResults = validateOptionalMaxResults(
    options.maxResults,
    "maxResults",
    minimumMaxResults,
    100,
    dependencies.createValidationError,
  );
  const paginationToken = validateOptionalPaginationToken(
    options.paginationToken,
    "paginationToken",
    dependencies.createValidationError,
  );
  return {
    postReadOptions: readPostReadOptions(options, dependencies),
    ...(maxResults === undefined ? {} : { maxResults }),
    ...(paginationToken === undefined ? {} : { paginationToken }),
  };
}

function readFollowingTimelineRequestInputs(
  options: XGatewayFollowingTimelineOptions,
  dependencies: CapabilityAdapterDependencies,
): FollowingTimelineRequestInputs {
  const maxResults =
    validateOptionalMaxResults(
      options.maxResults,
      "maxResults",
      1,
      100,
      dependencies.createValidationError,
    ) ?? 50;
  const maxUsers =
    validateOptionalMaxResults(
      options.maxUsers,
      "maxUsers",
      1,
      100,
      dependencies.createValidationError,
    ) ?? 25;
  const maxResultsPerUser =
    validateOptionalMaxResults(
      options.maxResultsPerUser,
      "maxResultsPerUser",
      5,
      100,
      dependencies.createValidationError,
    ) ?? 5;
  const paginationToken = validateOptionalPaginationToken(
    options.paginationToken,
    "paginationToken",
    dependencies.createValidationError,
  );
  if (paginationToken !== undefined) {
    throw dependencies.createValidationError(
      "followingTimeline.paginationToken is not supported until x-gateway implements a project-owned merged timeline cursor.",
    );
  }
  return {
    postReadOptions: readPostReadOptions(options, dependencies),
    maxResults,
    maxUsers,
    maxResultsPerUser,
  };
}

function buildRestTimelineRequestOptions(
  requestInputs: PostPageRequestInputs,
  paginationTokenField: RestPaginationTokenField,
): RestTimelineRequestOptions {
  return {
    ...(requestInputs.maxResults === undefined
      ? {}
      : { max_results: requestInputs.maxResults }),
    ...(requestInputs.paginationToken === undefined
      ? {}
      : paginationTokenField === "pagination_token"
        ? { pagination_token: requestInputs.paginationToken }
        : { next_token: requestInputs.paginationToken }),
    ...POST_LOOKUP_FIELDS,
  };
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
    if (typeof value === "string" && /^(0|[1-9][0-9]*)$/.test(value.trim())) {
      const parsed = Number.parseInt(value, 10);
      if (Number.isSafeInteger(parsed) && parsed >= 0) {
        return parsed;
      }
    }
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

  function readUsageIdentifier(value: unknown, fieldName: string): string {
    if (
      typeof value === "number" &&
      Number.isSafeInteger(value) &&
      value >= 0
    ) {
      return String(value);
    }
    return readUsageString(value, fieldName);
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
      clientAppId: readUsageIdentifier(
        clientApp.client_app_id,
        `${fieldName}.client_app_id`,
      ),
      usage:
        clientApp.usage === undefined
          ? []
          : readUsageEntryArray(clientApp.usage, `${fieldName}.usage`),
      usageResultCount:
        clientApp.usage_result_count === undefined
          ? 0
          : readUsageInteger(
              clientApp.usage_result_count,
              `${fieldName}.usage_result_count`,
            ),
    };
  }

  function readUsageClientAppArray(
    value: unknown,
    fieldName: string,
  ): readonly XGatewayUsageClientApp[] {
    if (value === undefined) {
      return [];
    }
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
    fallbackProjectId: string,
  ): XGatewayUsageProjectTimeline {
    if (value === undefined) {
      return {
        projectId: fallbackProjectId,
        usage: [],
      };
    }
    if (typeof value !== "object" || value === null) {
      throw createUsagePayloadError(
        `Field '${fieldName}' must be an object in the usage response.`,
      );
    }
    const projectTimeline = value as UsageApiProjectPayload;
    return {
      projectId:
        projectTimeline.project_id === undefined
          ? fallbackProjectId
          : readUsageIdentifier(
              projectTimeline.project_id,
              `${fieldName}.project_id`,
            ),
      usage:
        projectTimeline.usage === undefined
          ? []
          : readUsageEntryArray(projectTimeline.usage, `${fieldName}.usage`),
    };
  }

  function mapUsageTweetsPayload(payload: unknown): XGatewayUsageTweetsResult {
    if (typeof payload !== "object" || payload === null) {
      throw createUsagePayloadError(
        "The usage endpoint did not return an object payload.",
      );
    }
    const data = payload as UsageApiDataPayload;
    const projectId = readUsageIdentifier(data.project_id, "project_id");
    return {
      capResetDay: readUsageInteger(data.cap_reset_day, "cap_reset_day"),
      dailyClientAppUsage: readUsageClientAppArray(
        data.daily_client_app_usage,
        "daily_client_app_usage",
      ),
      dailyProjectUsage: readUsageProjectTimeline(
        data.daily_project_usage,
        "daily_project_usage",
        projectId,
      ),
      projectCap: readUsageInteger(data.project_cap, "project_cap"),
      projectId,
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

    // Keep this capability on the documented usage endpoint only. X surfaces
    // billing totals such as balance and console cost in the Developer Console,
    // not through a reviewed public billing API for this project.
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

  function createRestReadCapabilityMethods(
    client: TwitterApi,
    getAuthenticatedUserId: () => Promise<string>,
  ): Pick<
    XGatewayReadCapabilityAdapter,
    | "postGet"
    | "postReplies"
    | "timelineSearch"
    | "timelineHome"
    | "timelineFollowing"
    | "timelineUser"
    | "timelineMentions"
  > {
    const timelineHome = async (
      options: XGatewayTimelinePageOptions,
    ): Promise<XGatewayPostPage> => {
      const requestInputs = readPostPageRequestInputs(options, 5, dependencies);
      const response = await client.v2.homeTimeline({
        ...buildRestTimelineRequestOptions(requestInputs, "pagination_token"),
      });
      return mapPostPage(
        client,
        response.data as V2TimelinePayload,
        requestInputs.postReadOptions,
      );
    };

    const timelineFollowing = async (
      options: XGatewayFollowingTimelineOptions,
    ): Promise<XGatewayPostPage> => {
      const requestInputs = readFollowingTimelineRequestInputs(
        options,
        dependencies,
      );
      const authenticatedUserId = await getAuthenticatedUserId();
      const followingResponse = (await client.v2.following(
        authenticatedUserId,
        {
          max_results: requestInputs.maxUsers,
          "user.fields": ["id", "name", "username"],
        },
      )) as V2UserTimelinePayload;
      const followedUsers = (followingResponse.data ?? []).slice(
        0,
        requestInputs.maxUsers,
      );
      const pages = await Promise.all(
        followedUsers.map(async (user) => {
          const response = await client.v2.userTimeline(user.id, {
            ...buildRestTimelineRequestOptions(
              {
                postReadOptions: requestInputs.postReadOptions,
                maxResults: requestInputs.maxResultsPerUser,
              },
              "pagination_token",
            ),
          });
          return mapPostPage(
            client,
            response.data as V2TimelinePayload,
            requestInputs.postReadOptions,
          );
        }),
      );
      const posts = pages
        .flatMap((page) => page.posts)
        .sort((left, right) => {
          const rightTime =
            right.createdAt === undefined ? 0 : Date.parse(right.createdAt);
          const leftTime =
            left.createdAt === undefined ? 0 : Date.parse(left.createdAt);
          return rightTime - leftTime;
        })
        .slice(0, requestInputs.maxResults);
      return createPostPageFromMergedPosts(posts);
    };

    const timelineUser = async (
      options: XGatewayTimelineUserOptions,
    ): Promise<XGatewayPostPage> => {
      const requestInputs = readPostPageRequestInputs(options, 5, dependencies);
      const userId = normalizeRequiredInput(
        options.userId,
        "userId",
        dependencies.ensureRequired,
      );
      const response = await client.v2.userTimeline(userId, {
        ...buildRestTimelineRequestOptions(requestInputs, "pagination_token"),
      });
      return mapPostPage(
        client,
        response.data as V2TimelinePayload,
        requestInputs.postReadOptions,
      );
    };

    const timelineMentions = async (
      options: XGatewayTimelineUserOptions,
    ): Promise<XGatewayPostPage> => {
      const requestInputs = readPostPageRequestInputs(options, 5, dependencies);
      const userId = normalizeRequiredInput(
        options.userId,
        "userId",
        dependencies.ensureRequired,
      );
      const response = await client.v2.userMentionTimeline(userId, {
        ...buildRestTimelineRequestOptions(requestInputs, "pagination_token"),
      });
      return mapPostPage(
        client,
        response.data as V2TimelinePayload,
        requestInputs.postReadOptions,
      );
    };

    const timelineSearch = async (
      options: XGatewayTimelineSearchOptions,
    ): Promise<XGatewayPostPage> => {
      const requestInputs = readPostPageRequestInputs(
        options,
        10,
        dependencies,
      );
      const query = normalizeRequiredInput(
        options.query,
        "query",
        dependencies.ensureRequired,
      );
      const response = await client.v2.search(query, {
        ...buildRestTimelineRequestOptions(requestInputs, "next_token"),
      });
      return mapPostPage(
        client,
        response.data as V2TimelinePayload,
        requestInputs.postReadOptions,
      );
    };

    const postGet = async (
      options: XGatewayPostGetOptions,
    ): Promise<XGatewayPostLookupResult> => {
      const postId = normalizeRequiredInput(
        options.postId,
        "postId",
        dependencies.ensureRequired,
      );
      const postReadOptions = readPostReadOptions(options, dependencies);
      const response = await client.v2.singleTweet(postId, POST_LOOKUP_FIELDS);
      return mapPostLookupResult(
        client,
        response,
        postReadOptions,
        dependencies.createError,
      );
    };

    const postReplies = async (
      options: XGatewayPostRepliesOptions,
    ): Promise<XGatewayPostPage> => {
      const requestInputs = readPostPageRequestInputs(
        options,
        10,
        dependencies,
      );
      const query = buildPostRepliesSearchQuery(options, dependencies);
      const response = await client.v2.search(query, {
        ...buildRestTimelineRequestOptions(requestInputs, "next_token"),
      });
      return mapPostPage(
        client,
        response.data as V2TimelinePayload,
        requestInputs.postReadOptions,
      );
    };

    return {
      postGet,
      postReplies,
      timelineSearch,
      timelineHome,
      timelineFollowing,
      timelineUser,
      timelineMentions,
    };
  }

  function createOauth1ReadCapabilityAdapter(): XGatewayReadCapabilityAdapter {
    const client = createOauth1RestClient();
    const getAuthenticatedUserId = async (): Promise<string> => {
      const user = await client.v1.verifyCredentials({
        include_entities: false,
        skip_status: true,
      });
      return user.id_str;
    };
    const readMethods = createRestReadCapabilityMethods(
      client,
      getAuthenticatedUserId,
    );

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
          summary: "API usage statistics require bearer auth",
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
      ...readMethods,
    };
  }

  function createBearerReadCapabilityAdapter(): XGatewayReadCapabilityAdapter {
    const client = createBearerRestClient();
    const getAuthenticatedUserId = async (): Promise<string> => {
      const response = await client.v2.me({
        "user.fields": ["id", "name", "username"],
      });
      return mapBearerAccountProfile(response, dependencies.createError).id;
    };
    const readMethods = createRestReadCapabilityMethods(
      client,
      getAuthenticatedUserId,
    );

    return {
      adapterKind: "rest-bearer",
      accountMe: async () => {
        const response = await client.v2.me({
          "user.fields": ["id", "name", "username"],
        });
        return mapBearerAccountProfile(response, dependencies.createError);
      },
      usageTweets: fetchUsageTweets,
      ...readMethods,
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
        const postId = normalizeRequiredInput(
          options.postId,
          "postId",
          dependencies.ensureRequired,
        );
        return client.v2.deleteTweet(postId);
      },
      postReply: async (options: XGatewayPostReplyOptions) => {
        const text = dependencies.ensureRequired(options.text, "text");
        const replyToPostId = normalizeRequiredInput(
          options.replyToPostId,
          "replyToPostId",
          dependencies.ensureRequired,
        );
        return client.v2.reply(
          text,
          replyToPostId,
          await buildMediaPayload(options.attachments),
        );
      },
      postQuote: async (options: XGatewayPostQuoteOptions) => {
        const text = dependencies.ensureRequired(options.text, "text");
        const quotedPostId = normalizeRequiredInput(
          options.quotedPostId,
          "quotedPostId",
          dependencies.ensureRequired,
        );
        return client.v2.quote(
          text,
          quotedPostId,
          await buildMediaPayload(options.attachments),
        );
      },
      postRepost: async (options: XGatewayPostRepostOptions) => {
        const postId = normalizeRequiredInput(
          options.postId,
          "postId",
          dependencies.ensureRequired,
        );
        const loggedUserId = await getLoggedUserId();
        return client.v2.retweet(loggedUserId, postId);
      },
      postUndoRepost: async (options: XGatewayPostRepostOptions) => {
        const postId = normalizeRequiredInput(
          options.postId,
          "postId",
          dependencies.ensureRequired,
        );
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
