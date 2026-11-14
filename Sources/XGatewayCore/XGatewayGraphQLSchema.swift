let publicGraphQLSchema = """
type Query {
  accountMe: AccountProfile!
  apiUsage(days: Int): ApiUsage!
  post(id: ID!, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): Post!
  searchPosts(query: String!, maxResults: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  homeTimeline(maxResults: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  followingTimeline(maxResults: Int, maxUsers: Int, maxResultsPerUser: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  userTimeline(userId: ID!, maxResults: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  mentionsTimeline(userId: ID!, maxResults: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
}

type Mutation {
  createPost(text: String!, attachments: [PostAttachmentInput!]): Post!
  deletePost(postId: ID!): DeletePostResult!
  replyToPost(text: String!, replyToPostId: ID!, attachments: [PostAttachmentInput!]): Post!
  quotePost(text: String!, quotedPostId: ID!, attachments: [PostAttachmentInput!]): Post!
  repostPost(postId: ID!): RepostResult!
  unrepostPost(postId: ID!): RepostResult!
}

input PostAttachmentInput {
  kind: String!
  filePath: String!
  altText: String
}

type AccountProfile {
  id: ID!
  username: String!
  name: String!
}

type MediaAsset {
  kind: String!
  contentType: String!
  sourceUrl: String!
  localFilePath: String
  previewImageUrl: String
}

type PostMetrics {
  likeCount: Int
  replyCount: Int
  repostCount: Int
  quoteCount: Int
  bookmarkCount: Int
  impressionCount: Int
}

type ReferencedPost {
  id: ID!
  text: String!
  promotionStatus: String!
  metrics: PostMetrics!
  createdAt: String
  conversationId: String
  replyToUserId: String
  author: AccountProfile
  media: [MediaAsset!]
  relation: String!
  replyTo: ReferencedPostLevel2
  quote: ReferencedPostLevel2
  repost: ReferencedPostLevel2
}

type ReferencedPostLevel2 {
  id: ID!
  text: String!
  promotionStatus: String!
  metrics: PostMetrics!
  createdAt: String
  conversationId: String
  replyToUserId: String
  author: AccountProfile
  media: [MediaAsset!]
  relation: String!
}

type Post {
  id: ID!
  text: String!
  promotionStatus: String!
  metrics: PostMetrics!
  createdAt: String
  conversationId: String
  replyToUserId: String
  author: AccountProfile
  media: [MediaAsset!]
  referencedPosts: [ReferencedPost!]
  replies(maxResults: Int, paginationToken: String, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  replyTo: ReferencedPost
  quote: ReferencedPost
  repost: ReferencedPost
}

type PostLookupResult {
  post: Post!
}

type PostPage {
  posts: [Post!]!
  pageInfo: PageInfo!
}

type PageInfo {
  resultCount: Int!
  nextToken: String
  previousToken: String
  newestId: String
  oldestId: String
}

type ApiUsage {
  projectUsage: Int
}

type DeletePostResult {
  deleted: Boolean!
}

type RepostResult {
  id: ID!
  reposted: Boolean!
}
"""
