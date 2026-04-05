import { buildSchema } from "graphql";

const ACCOUNT_TYPE_DEFINITION = /* GraphQL */ `
  type Account {
    id: String!
    username: String!
    name: String!
  }
`;

const POST_SHARED_FIELDS = /* GraphQL */ `
    id: String!
    text: String!
    createdAt: String
    conversationId: String
    replyToUserId: String
    author: Account
    media: [MediaAsset!]
`;

const MEDIA_TYPE_DEFINITION = /* GraphQL */ `
  type MediaAsset {
    kind: String!
    contentType: String!
    sourceUrl: String!
    localFilePath: String
    previewImageUrl: String
  }
`;

export const PUBLIC_GRAPHQL_TYPE_DEFS = /* GraphQL */ `
  input PostAttachmentInput {
    kind: String!
    filePath: String!
    altText: String
  }

  ${ACCOUNT_TYPE_DEFINITION}
  ${MEDIA_TYPE_DEFINITION}

  type ReferencedPost {
${POST_SHARED_FIELDS}
    relation: String!
    replyTo: ReferencedPostLevel2
    quote: ReferencedPostLevel2
    repost: ReferencedPostLevel2
  }

  type ReferencedPostLevel2 {
${POST_SHARED_FIELDS}
    relation: String!
  }

  type Post {
${POST_SHARED_FIELDS}
    referencedPosts: [ReferencedPost!]
    replyTo: ReferencedPost
    quote: ReferencedPost
    repost: ReferencedPost
  }

  type PageInfo {
    resultCount: Int!
    nextToken: String
    previousToken: String
    newestId: String
    oldestId: String
  }

  type UsageDay {
    date: String!
    usage: Int!
  }

  type ClientAppUsage {
    clientAppId: String!
    usageResultCount: Int!
    usage: [UsageDay!]!
  }

  type ProjectUsageTimeline {
    projectId: String!
    usage: [UsageDay!]!
  }

  type PostUsage {
    capResetDay: Int!
    dailyClientAppUsage: [ClientAppUsage!]!
    dailyProjectUsage: ProjectUsageTimeline!
    projectCap: Int!
    projectId: String!
    projectUsage: Int!
  }

  type PostPage {
    posts: [Post!]!
    pageInfo: PageInfo!
  }

  type CreatedPost {
    id: String!
    text: String!
  }

  type DeletedPost {
    id: String!
    deleted: Boolean!
  }

  type RepostMutationResult {
    id: String!
    reposted: Boolean!
  }

  type Query {
    accountMe: Account!
    postUsage(days: Int): PostUsage!
    post(
      id: String!
      mediaRootDir: String
      downloadMedia: Boolean
      forceDownload: Boolean
    ): Post!
    searchPosts(
      query: String!
      maxResults: Int
      paginationToken: String
      mediaRootDir: String
      downloadMedia: Boolean
      forceDownload: Boolean
    ): PostPage!
    homeTimeline(
      maxResults: Int
      paginationToken: String
      mediaRootDir: String
      downloadMedia: Boolean
      forceDownload: Boolean
    ): PostPage!
    userTimeline(
      userId: String!
      maxResults: Int
      paginationToken: String
      mediaRootDir: String
      downloadMedia: Boolean
      forceDownload: Boolean
    ): PostPage!
    mentionsTimeline(
      userId: String!
      maxResults: Int
      paginationToken: String
      mediaRootDir: String
      downloadMedia: Boolean
      forceDownload: Boolean
    ): PostPage!
  }

  type Mutation {
    createPost(text: String!, attachments: [PostAttachmentInput!]): CreatedPost!
    deletePost(postId: String!): DeletedPost!
    replyToPost(
      text: String!
      replyToPostId: String!
      attachments: [PostAttachmentInput!]
    ): CreatedPost!
    quotePost(
      text: String!
      quotedPostId: String!
      attachments: [PostAttachmentInput!]
    ): CreatedPost!
    repostPost(postId: String!): RepostMutationResult!
    unrepostPost(postId: String!): RepostMutationResult!
  }
`;

export const PUBLIC_GRAPHQL_SCHEMA = buildSchema(PUBLIC_GRAPHQL_TYPE_DEFS);
