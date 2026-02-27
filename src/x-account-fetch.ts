import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { ApiResponseError, TwitterApi } from "twitter-api-v2";

type MinimalUser = Readonly<{
  id: string;
  username: string;
  name: string;
}>;

type MinimalTweet = Readonly<{
  id: string;
  text: string;
  authorId: string | undefined;
  authorUsername: string | undefined;
  authorName: string | undefined;
  createdAt: string | undefined;
  likeCount: number | undefined;
  replyCount: number | undefined;
  retweetCount: number | undefined;
  inReplyToUserId: string | undefined;
  referencedTweets: readonly Readonly<{
    id: string;
    type: string;
    authorUsername: string | undefined;
  }>[];
  media: readonly Readonly<{
    mediaKey: string;
    type: string;
    url: string | undefined;
    previewImageUrl: string | undefined;
  }>[];
}>;

type SavedSnapshot = Readonly<{
  generatedAt: string;
  targetAccount: MinimalUser;
  limits: Readonly<{
    likedTweets: number;
    followingUsers: number;
    tweetsPerFollowingUser: number;
  }>;
  likedTweets: readonly MinimalTweet[];
  followingUsers: readonly MinimalUser[];
  tweetsByFollowingUser: Readonly<Record<string, readonly MinimalTweet[]>>;
  warnings: readonly string[];
}>;

type ApiUser = Readonly<{
  id: string;
  username?: string;
  name?: string;
}>;

type ApiTweet = Readonly<{
  id: string;
  text?: string;
  author_id?: string;
  created_at?: string;
  in_reply_to_user_id?: string;
  referenced_tweets?: readonly Readonly<{
    id: string;
    type: string;
  }>[];
  attachments?: Readonly<{
    media_keys?: readonly string[];
  }>;
  public_metrics?: Readonly<{
    like_count?: number;
    reply_count?: number;
    retweet_count?: number;
  }>;
}>;

type ApiMedia = Readonly<{
  media_key: string;
  type: string;
  url?: string;
  preview_image_url?: string;
}>;

const API_MIN_TWEET_PAGE_SIZE = 5;
const DEFAULT_LIKED_LIMIT = 5;
const DEFAULT_FOLLOWING_LIMIT = 3;
const DEFAULT_TWEETS_PER_FOLLOWING_USER = 3;
const DEFAULT_OUTPUT_DIR = "tmp/x-account-data";

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value || value.trim().length === 0) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function optionalEnv(name: string): string | undefined {
  const value = process.env[name];
  if (!value) {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function parseSmallPositiveInt(
  rawValue: string | undefined,
  fallback: number,
  maxValue: number,
): number {
  if (!rawValue) {
    return fallback;
  }
  const parsed = Number.parseInt(rawValue, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return Math.min(parsed, maxValue);
}

function toMinimalUser(user: ApiUser): MinimalUser {
  return {
    id: user.id,
    username: user.username ?? "",
    name: user.name ?? "",
  };
}

function createUserMap(
  users: readonly ApiUser[] | undefined,
): ReadonlyMap<string, ApiUser> {
  return new Map((users ?? []).map((user) => [user.id, user]));
}

function toMinimalTweet(
  tweet: ApiTweet,
  usersById: ReadonlyMap<string, ApiUser>,
  tweetsById: ReadonlyMap<string, ApiTweet>,
  mediaByKey: ReadonlyMap<string, ApiMedia>,
): MinimalTweet {
  const author = tweet.author_id ? usersById.get(tweet.author_id) : undefined;
  const referencedTweets = (tweet.referenced_tweets ?? []).map((reference) => {
    const referencedTweet = tweetsById.get(reference.id);
    const referencedAuthorId = referencedTweet?.author_id;
    return {
      id: reference.id,
      type: reference.type,
      authorUsername: referencedAuthorId
        ? usersById.get(referencedAuthorId)?.username
        : undefined,
    };
  });
  const media = (tweet.attachments?.media_keys ?? []).map((mediaKey) => {
    const medium = mediaByKey.get(mediaKey);
    return {
      mediaKey,
      type: medium?.type ?? "unknown",
      url: medium?.url,
      previewImageUrl: medium?.preview_image_url,
    };
  });
  return {
    id: tweet.id,
    text: tweet.text ?? "",
    authorId: tweet.author_id,
    authorUsername: author?.username,
    authorName: author?.name,
    createdAt: tweet.created_at,
    likeCount: tweet.public_metrics?.like_count,
    replyCount: tweet.public_metrics?.reply_count,
    retweetCount: tweet.public_metrics?.retweet_count,
    inReplyToUserId: tweet.in_reply_to_user_id,
    referencedTweets,
    media,
  };
}

function summarizeApiError(error: unknown): string {
  if (error instanceof ApiResponseError) {
    const title = error.data.title ?? "API response error";
    const detail = error.data.detail ?? error.message;
    return `HTTP ${error.code}: ${title} - ${detail}`;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return "Unknown error";
}

async function run(): Promise<void> {
  const appKey = optionalEnv("X_CONSUMER_KEY");
  const appSecret = optionalEnv("X_SECRET_KEY");
  const accessToken = optionalEnv("X_ACCESS_TOKEN");
  const accessSecret = optionalEnv("X_ACCESS_TOKEN_SECRET");

  const accountUsername = process.env["X_ACCOUNT_USERNAME"];
  const likesLimit = parseSmallPositiveInt(
    process.env["X_LIKED_LIMIT"],
    DEFAULT_LIKED_LIMIT,
    20,
  );
  const followingLimit = parseSmallPositiveInt(
    process.env["X_FOLLOWING_LIMIT"],
    DEFAULT_FOLLOWING_LIMIT,
    20,
  );
  const tweetsPerFollowingUser = parseSmallPositiveInt(
    process.env["X_TWEETS_PER_FOLLOWING_USER"],
    DEFAULT_TWEETS_PER_FOLLOWING_USER,
    5,
  );
  const outputDir = process.env["X_OUTPUT_DIR"] ?? DEFAULT_OUTPUT_DIR;

  if (!accountUsername) {
    throw new Error(
      "Set X_ACCOUNT_USERNAME in environment. Example: export X_ACCOUNT_USERNAME=your_handle",
    );
  }

  const client =
    appKey && appSecret && accessToken && accessSecret
      ? new TwitterApi({
          appKey,
          appSecret,
          accessToken,
          accessSecret,
        }).readOnly
      : new TwitterApi(requiredEnv("X_BEARER_TOKEN")).readOnly;

  const me = await client.v2.userByUsername(accountUsername, {
    "user.fields": ["id", "name", "username"],
  });

  if (!me.data) {
    throw new Error(
      `Could not resolve account by username: ${accountUsername}`,
    );
  }

  const targetAccount = toMinimalUser(me.data);

  const warnings: string[] = [];

  let likedTweets: readonly MinimalTweet[] = [];
  try {
    const likedPaginator = await client.v2.userLikedTweets(targetAccount.id, {
      max_results: Math.max(likesLimit, API_MIN_TWEET_PAGE_SIZE),
      expansions: [
        "author_id",
        "attachments.media_keys",
        "referenced_tweets.id",
        "referenced_tweets.id.author_id",
      ],
      "tweet.fields": [
        "id",
        "text",
        "author_id",
        "created_at",
        "public_metrics",
        "attachments",
        "referenced_tweets",
        "in_reply_to_user_id",
      ],
      "user.fields": ["id", "name", "username"],
      "media.fields": ["media_key", "type", "url", "preview_image_url"],
    });

    const likedUsersById = createUserMap(likedPaginator.includes.users);
    const likedTweetsById = new Map(
      likedPaginator.includes.tweets.map((tweet) => [
        tweet.id,
        tweet as ApiTweet,
      ]),
    );
    const likedMediaByKey = new Map(
      likedPaginator.includes.media.map((medium) => [
        medium.media_key,
        medium as ApiMedia,
      ]),
    );
    likedTweets = likedPaginator.tweets
      .slice(0, likesLimit)
      .map((tweet) =>
        toMinimalTweet(
          tweet as ApiTweet,
          likedUsersById,
          likedTweetsById,
          likedMediaByKey,
        ),
      );
  } catch (error: unknown) {
    warnings.push(`liked_tweets skipped: ${summarizeApiError(error)}`);
  }

  let followingUsers: readonly MinimalUser[] = [];
  try {
    const followingResponse = await client.v2.following(targetAccount.id, {
      max_results: followingLimit,
      "user.fields": ["id", "name", "username"],
    });

    followingUsers = (followingResponse.data ?? []).map((user) =>
      toMinimalUser(user as ApiUser),
    );
  } catch (error: unknown) {
    warnings.push(`following skipped: ${summarizeApiError(error)}`);
  }

  const tweetsByFollowingUser: Record<string, readonly MinimalTweet[]> = {};
  for (const user of followingUsers) {
    try {
      const timelinePaginator = await client.v2.userTimeline(user.id, {
        max_results: API_MIN_TWEET_PAGE_SIZE,
        expansions: [
          "author_id",
          "attachments.media_keys",
          "referenced_tweets.id",
          "referenced_tweets.id.author_id",
        ],
        "tweet.fields": [
          "id",
          "text",
          "author_id",
          "created_at",
          "public_metrics",
          "attachments",
          "referenced_tweets",
          "in_reply_to_user_id",
        ],
        "user.fields": ["id", "name", "username"],
        "media.fields": ["media_key", "type", "url", "preview_image_url"],
      });

      const usersById = createUserMap(timelinePaginator.includes.users);
      const tweetsById = new Map(
        timelinePaginator.includes.tweets.map((tweet) => [
          tweet.id,
          tweet as ApiTweet,
        ]),
      );
      const mediaByKey = new Map(
        timelinePaginator.includes.media.map((medium) => [
          medium.media_key,
          medium as ApiMedia,
        ]),
      );
      tweetsByFollowingUser[user.id] = timelinePaginator.tweets
        .slice(0, tweetsPerFollowingUser)
        .map((tweet) =>
          toMinimalTweet(tweet as ApiTweet, usersById, tweetsById, mediaByKey),
        );
    } catch (error: unknown) {
      warnings.push(
        `user_timeline skipped for ${user.username}: ${summarizeApiError(error)}`,
      );
      tweetsByFollowingUser[user.id] = [];
    }
  }

  const snapshot: SavedSnapshot = {
    generatedAt: new Date().toISOString(),
    targetAccount,
    limits: {
      likedTweets: likesLimit,
      followingUsers: followingLimit,
      tweetsPerFollowingUser,
    },
    likedTweets,
    followingUsers,
    tweetsByFollowingUser,
    warnings,
  };

  await mkdir(outputDir, { recursive: true });
  const timestamp = snapshot.generatedAt.replaceAll(":", "-");
  const outputPath = path.join(
    outputDir,
    `x-account-snapshot-${timestamp}.json`,
  );
  await writeFile(
    outputPath,
    `${JSON.stringify(snapshot, null, 2)}\n`,
    "utf-8",
  );

  console.log("Snapshot saved.");
  console.log(`Account: @${targetAccount.username} (${targetAccount.id})`);
  console.log(`Liked tweets captured: ${likedTweets.length}`);
  console.log(`Following users captured: ${followingUsers.length}`);
  console.log(`Warnings: ${warnings.length}`);
  console.log(`Output: ${outputPath}`);
}

run().catch((error: unknown) => {
  if (error instanceof Error) {
    console.error(`Failed: ${error.message}`);
  } else {
    console.error("Failed with unknown error.");
  }
  process.exitCode = 1;
});
