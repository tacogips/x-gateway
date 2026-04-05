import { buildSchema } from "graphql";

export const PUBLIC_GRAPHQL_TYPE_DEFS = /* GraphQL */ `
  input PostAttachmentInput {
    kind: String!
    filePath: String!
    altText: String
  }

  type Account {
    id: String!
    username: String!
    name: String!
  }

  type ReferencedPost {
    id: String!
    text: String!
    createdAt: String
    conversationId: String
    replyToUserId: String
    author: Account
    relation: String!
  }

  type Post {
    id: String!
    text: String!
    createdAt: String
    conversationId: String
    replyToUserId: String
    author: Account
    referencedPosts: [ReferencedPost!]
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
    post(id: String!): Post!
    searchPosts(
      query: String!
      maxResults: Int
      paginationToken: String
    ): PostPage!
    homeTimeline(maxResults: Int, paginationToken: String): PostPage!
    userTimeline(
      userId: String!
      maxResults: Int
      paginationToken: String
    ): PostPage!
    mentionsTimeline(
      userId: String!
      maxResults: Int
      paginationToken: String
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
