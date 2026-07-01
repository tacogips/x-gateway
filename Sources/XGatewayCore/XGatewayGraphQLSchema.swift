let publicGraphQLSchema = """
type Query {
  accountMe: AccountProfile!
  apiUsage(days: Int): ApiUsage!
  user(id: ID!): AccountProfile!
  userByUsername(username: String!): AccountProfile!
  users(ids: [ID!]!): UserPage!
  usersByUsernames(usernames: [String!]!): UserPage!
  followers(userId: ID!, maxResults: Int, paginationToken: String): UserPage!
  following(userId: ID!, maxResults: Int, paginationToken: String): UserPage!
  post(id: ID!, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): Post!
  posts(ids: [ID!]!, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  likedPosts(userId: ID!, maxResults: Int, paginationToken: String, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  postLikingUsers(postId: ID!, maxResults: Int, paginationToken: String): UserPage!
  postRepostingUsers(postId: ID!, maxResults: Int, paginationToken: String): UserPage!
  postQuotes(postId: ID!, maxResults: Int, paginationToken: String, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  searchAllPosts(
    query: String!,
    maxResults: Int,
    startTime: String,
    endTime: String,
    sinceId: String,
    untilId: String,
    nextToken: String,
    paginationToken: String,
    sortOrder: String,
    mediaRootDir: String,
    downloadMedia: Boolean,
    forceDownload: Boolean,
    includePromoted: Boolean
  ): PostPage!
  searchUsers(query: String!, maxResults: Int, nextToken: String): UserPage!
  searchNews(query: String!, maxResults: Int, maxAgeHours: Int): NewsPage!
  news(id: ID!): NewsStory!
  trendsByWoeid(woeid: Int!, maxTrends: Int): TrendPage!
  recentPostCounts(query: String!, startTime: String, endTime: String, sinceId: String, untilId: String, nextToken: String, paginationToken: String, granularity: String): PostCountPage!
  bookmarks(maxResults: Int, paginationToken: String, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  bookmarkFolders(maxResults: Int, paginationToken: String): BookmarkFolderPage!
  bookmarksByFolder(folderId: ID!, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  mutedUsers(userId: ID!, maxResults: Int, paginationToken: String): UserPage!
  blockedUsers(userId: ID!, maxResults: Int, paginationToken: String): UserPage!
  list(id: ID!): List!
  ownedLists(userId: ID!, maxResults: Int, paginationToken: String): ListPage!
  followedLists(userId: ID!, maxResults: Int, paginationToken: String): ListPage!
  listMemberships(userId: ID!, maxResults: Int, paginationToken: String): ListPage!
  pinnedLists(userId: ID!): ListPage!
  listFollowers(listId: ID!, maxResults: Int, paginationToken: String): UserPage!
  listMembers(listId: ID!, maxResults: Int, paginationToken: String): UserPage!
  listPosts(listId: ID!, maxResults: Int, paginationToken: String, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  dmEvents(maxResults: Int, paginationToken: String, eventTypes: [String!]): DirectMessageEventPage!
  dmEvent(id: ID!): DirectMessageEvent!
  dmConversationEvents(participantId: ID!, maxResults: Int, paginationToken: String, eventTypes: [String!]): DirectMessageEventPage!
  dmConversationEventsById(conversationId: ID!, maxResults: Int, paginationToken: String, eventTypes: [String!]): DirectMessageEventPage!
  searchPosts(query: String!, maxResults: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  homeTimeline(maxResults: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  followingTimeline(maxResults: Int, maxUsers: Int, maxResultsPerUser: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  userTimeline(userId: ID!, maxResults: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  mentionsTimeline(userId: ID!, maxResults: Int, mediaRootDir: String, downloadMedia: Boolean, forceDownload: Boolean, includePromoted: Boolean): PostPage!
  complianceJobs(type: String, status: String): OpenAPIResult!
  complianceJob(id: ID!): OpenAPIResult!
  communitiesSearch(query: String!, maxResults: Int, nextToken: String): OpenAPIResult!
  community(id: ID!): OpenAPIResult!
  communityNotesWritten(testMode: Boolean, maxResults: Int, paginationToken: String): OpenAPIResult!
  communityPostsEligibleForNotes(testMode: Boolean, postSelection: String, maxResults: Int, paginationToken: String): OpenAPIResult!
  communityNote(id: ID!): OpenAPIResult!
  allPostCounts(query: String!, startTime: String, endTime: String, sinceId: String, untilId: String, nextToken: String, paginationToken: String, granularity: String): OpenAPIResult!
  postAnalytics(postIds: [ID!]!, startTime: String, endTime: String, granularity: String): OpenAPIResult!
  postReposts(postId: ID!, maxResults: Int, paginationToken: String): OpenAPIResult!
  media(mediaKeys: [String!]!): OpenAPIResult!
  mediaByKey(mediaKey: String!): OpenAPIResult!
  mediaAnalytics(mediaKeys: [String!]!, startTime: String, endTime: String, granularity: String): OpenAPIResult!
  mediaUploadStatus(mediaId: ID!): OpenAPIResult!
  insights28hr(postIds: [ID!]!, granularity: String!, requestedMetrics: [String!]!): OpenAPIResult!
  insightsHistorical(postIds: [ID!]!, startTime: String!, endTime: String!, granularity: String!, requestedMetrics: [String!]!): OpenAPIResult!
  personalizedTrends: OpenAPIResult!
  publicKeys(userIds: [ID!]!): OpenAPIResult!
  userPublicKeys(userId: ID!): OpenAPIResult!
  userAffiliates(userId: ID!, maxResults: Int, paginationToken: String): OpenAPIResult!
  repostsOfMe(maxResults: Int, paginationToken: String): OpenAPIResult!
  webhooks: OpenAPIResult!
  accountActivitySubscriptionCount: OpenAPIResult!
  accountActivitySubscriptions(webhookId: ID!): OpenAPIResult!
  validateAccountActivitySubscription(webhookId: ID!): OpenAPIResult!
  activitySubscriptions: OpenAPIResult!
  openAPISpec: OpenAPIResult!
  chatConversations(maxResults: Int, paginationToken: String): OpenAPIResult!
  chatConversation(id: ID!): OpenAPIResult!
  chatConversationEvents(id: ID!, maxResults: Int, paginationToken: String): OpenAPIResult!
  spaces(ids: [ID!]!): SpacePage!
  spacesByCreatorIds(userIds: [ID!]!): SpacePage!
  searchSpaces(query: String!, state: String, maxResults: Int): SpacePage!
  space(id: ID!): Space!
  spaceBuyers(id: ID!, maxResults: Int, paginationToken: String): UserPage!
  spacePosts(id: ID!, maxResults: Int): PostPage!
  streamRules(ids: [ID!], maxResults: Int, paginationToken: String): StreamRulePage!
  streamRuleCounts: OpenAPIResult!
  downloadChatMedia(id: ID!, mediaHashKey: String!, outputPath: String!): OpenAPIResult!
  downloadDirectMessageMedia(dmId: ID!, mediaId: ID!, resourceId: String!, outputPath: String!): OpenAPIResult!
}

type Mutation {
  createPost(text: String!, attachments: [PostAttachmentInput!]): Post!
  deletePost(postId: ID!): DeletePostResult!
  replyToPost(text: String!, replyToPostId: ID!, attachments: [PostAttachmentInput!]): Post!
  quotePost(text: String!, quotedPostId: ID!, attachments: [PostAttachmentInput!]): Post!
  repostPost(postId: ID!): RepostResult!
  unrepostPost(postId: ID!): RepostResult!
  bookmarkPost(postId: ID!): BookmarkResult!
  removeBookmark(postId: ID!): BookmarkResult!
  likePost(postId: ID!): LikeResult!
  unlikePost(postId: ID!): LikeResult!
  followUser(targetUserId: ID!): FollowResult!
  unfollowUser(targetUserId: ID!): FollowResult!
  muteUser(targetUserId: ID!): MuteResult!
  unmuteUser(targetUserId: ID!): MuteResult!
  createList(name: String!, description: String, private: Boolean): List!
  updateList(listId: ID!, name: String, description: String, private: Boolean): UpdateResult!
  deleteList(listId: ID!): DeleteResult!
  addListMember(listId: ID!, userId: ID!): ListMemberResult!
  removeListMember(listId: ID!, userId: ID!): ListMemberResult!
  followList(listId: ID!): ListRelationshipResult!
  unfollowList(listId: ID!): ListRelationshipResult!
  pinList(listId: ID!): ListPinResult!
  unpinList(listId: ID!): ListPinResult!
  createDirectMessage(participantId: ID!, text: String!, attachments: [PostAttachmentInput!]): DirectMessageEvent!
  createDirectMessageInConversation(conversationId: ID!, text: String!, attachments: [PostAttachmentInput!]): DirectMessageEvent!
  createDirectMessageConversation(participantIds: [ID!]!, text: String!, attachments: [PostAttachmentInput!]): DirectMessageEvent!
  deleteDirectMessage(eventId: ID!): DeleteResult!
  createArticleDraft(title: String!, text: String, contentStateJSON: String): ArticleDraftResult!
  publishArticle(articleId: ID!): ArticlePublishResult!
  createComplianceJob(type: String!, name: String!, resumable: Boolean): OpenAPIResult!
  createCommunityNote(postId: ID!, classification: String!, text: String!, testMode: Boolean): OpenAPIResult!
  deleteCommunityNote(id: ID!): OpenAPIResult!
  evaluateCommunityNote(postId: ID!, noteText: String!): OpenAPIResult!
  hideReply(postId: ID!, hidden: Boolean!): OpenAPIResult!
  blockDirectMessages(userId: ID!): OpenAPIResult!
  unblockDirectMessages(userId: ID!): OpenAPIResult!
  initializeMediaUpload(mediaType: String!, totalBytes: Int!, mediaCategory: String): OpenAPIResult!
  finalizeMediaUpload(mediaId: ID!): OpenAPIResult!
  createMediaMetadata(mediaId: ID!, altText: String!): OpenAPIResult!
  createMediaSubtitles(mediaId: ID!, languageCode: String!, displayName: String!, filePath: String!): OpenAPIResult!
  deleteMediaSubtitles(mediaId: ID!, languageCode: String!): OpenAPIResult!
  createWebhook(url: String!): OpenAPIResult!
  deleteWebhook(webhookId: ID!): OpenAPIResult!
  validateWebhook(webhookId: ID!): OpenAPIResult!
  replayWebhook(webhookId: ID!, fromDate: String!, toDate: String!): OpenAPIResult!
  createAccountActivitySubscription(webhookId: ID!): OpenAPIResult!
  deleteAccountActivitySubscription(webhookId: ID!, userId: ID!): OpenAPIResult!
  createActivitySubscription(eventType: String!, filter: String!, tag: String, webhookId: ID): OpenAPIResult!
  updateActivitySubscription(subscriptionId: ID!, eventType: String, filter: String, tag: String, webhookId: ID): OpenAPIResult!
  deleteActivitySubscription(subscriptionId: ID!): OpenAPIResult!
  deleteActivitySubscriptions(subscriptionIds: [ID!]!): OpenAPIResult!
  initializeChatConversationKeys(id: ID!): OpenAPIResult!
  addChatGroupMembers(id: ID!, participantIds: [ID!]!): OpenAPIResult!
  sendEncryptedChatMessage(id: ID!, messageId: String!, encodedMessageCreateEvent: String!, encodedMessageEventSignature: String, conversationToken: String): OpenAPIResult!
  markChatConversationRead(id: ID!): OpenAPIResult!
  sendChatTypingIndicator(id: ID!): OpenAPIResult!
  addUserPublicKey(
    userId: ID!,
    version: String!,
    publicKey: String!,
    signingPublicKey: String!,
    identityPublicKeySignature: String,
    signingPublicKeySignature: String,
    publicKeyFingerprint: String,
    registrationMethod: String,
    generateVersion: Boolean
  ): OpenAPIResult!
  createEncryptedChatGroupConversation(
    conversationId: ID!,
    conversationKeyVersion: String!,
    conversationParticipantKeysJSON: String!,
    groupMembers: [ID!]!,
    actionSignaturesJSON: String,
    base64EncodedKeyRotation: String,
    groupAdmins: [ID!],
    groupName: String,
    groupDescription: String,
    groupAvatarUrl: String,
    ttlMsec: String
  ): OpenAPIResult!
  initializeChatGroup: OpenAPIResult!
  initializeChatMediaUpload(conversationId: ID!, totalBytes: Int!): OpenAPIResult!
  finalizeChatMediaUpload(id: ID!, conversationId: ID!, mediaHashKey: String!, messageId: String, numParts: String, ttlMsec: String): OpenAPIResult!
  uploadMedia(filePath: String!, mediaCategory: String!, mediaType: String, shared: Boolean, additionalOwners: [ID!]): OpenAPIResult!
  appendMediaUpload(mediaId: ID!, segmentIndex: Int!, filePath: String!): OpenAPIResult!
  appendChatMediaUpload(id: ID!, conversationId: ID!, mediaHashKey: String!, segmentIndex: Int!, filePath: String!): OpenAPIResult!
  updateStreamRules(addJSON: String, deleteJSON: String, dryRun: Boolean, deleteAll: Boolean): StreamRuleUpdateResult!
}

scalar JSON

type OpenAPIResult {
  ok: Boolean!
  payload: JSON
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

type UserPage {
  users: [AccountProfile!]!
  pageInfo: PageInfo!
}

type BookmarkFolder {
  id: ID!
  name: String!
}

type BookmarkFolderPage {
  folders: [BookmarkFolder!]!
  pageInfo: PageInfo!
}

type List {
  id: ID!
  name: String!
  description: String
  createdAt: String
  ownerId: ID
  followerCount: Int
  memberCount: Int
  private: Boolean
}

type ListPage {
  lists: [List!]!
  pageInfo: PageInfo!
}

type DirectMessageEvent {
  id: ID!
  eventType: String!
  text: String
  createdAt: String
  conversationId: ID
  senderId: ID
  participantIds: [ID!]
  referencedPostIds: [ID!]
  attachmentMediaKeys: [String!]
  attachmentCardIds: [String!]
}

type DirectMessageEventPage {
  events: [DirectMessageEvent!]!
  pageInfo: PageInfo!
}

type NewsStory {
  id: ID!
  name: String!
  summary: String
  category: String
  hook: String
  lastUpdatedAt: String
  keywords: [String!]
  postIds: [ID!]
}

type NewsPage {
  stories: [NewsStory!]!
  pageInfo: PageInfo!
}

type Trend {
  name: String!
  postCount: Int
}

type TrendPage {
  trends: [Trend!]!
  pageInfo: PageInfo!
}

type Space {
  id: ID!
  state: String
  title: String
  creatorId: ID
  hostIds: [ID!]
  speakerIds: [ID!]
  invitedUserIds: [ID!]
  participantCount: Int
  subscriberCount: Int
  createdAt: String
  startedAt: String
  endedAt: String
  scheduledStart: String
  updatedAt: String
  lang: String
  isTicketed: Boolean
  topicIds: [ID!]
}

type SpacePage {
  spaces: [Space!]!
  pageInfo: PageInfo!
}

type StreamRule {
  id: ID!
  value: String!
  tag: String
}

type StreamRuleSummary {
  created: Int
  deleted: Int
  invalid: Int
  notCreated: Int
  notDeleted: Int
  valid: Int
}

type StreamRuleError {
  title: String
  type: String
  detail: String
  status: Int
}

type StreamRulePage {
  rules: [StreamRule!]!
  pageInfo: PageInfo!
  sent: String
  summary: StreamRuleSummary
}

type StreamRuleUpdateResult {
  rules: [StreamRule!]!
  pageInfo: PageInfo!
  sent: String
  summary: StreamRuleSummary
  errors: [StreamRuleError!]
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

type PostCountBucket {
  start: String!
  end: String!
  postCount: Int!
}

type PostCountPage {
  counts: [PostCountBucket!]!
  pageInfo: PageInfo!
  totalPostCount: Int!
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

type BookmarkResult {
  id: ID!
  bookmarked: Boolean!
}

type LikeResult {
  id: ID!
  liked: Boolean!
}

type FollowResult {
  id: ID!
  following: Boolean!
}

type MuteResult {
  id: ID!
  muting: Boolean!
}

type DeleteResult {
  id: ID!
  deleted: Boolean!
}

type UpdateResult {
  id: ID!
  updated: Boolean!
}

type ListMemberResult {
  id: ID!
  isMember: Boolean!
}

type ListRelationshipResult {
  id: ID!
  following: Boolean!
}

type ListPinResult {
  id: ID!
  pinned: Boolean!
}

type ArticleDraftResult {
  id: ID!
  title: String!
}

type ArticlePublishResult {
  postId: ID!
}
"""
