import Foundation
import XGatewayCore

func runMCPParitySmokeTests() throws {
    let readCli = XGatewayCLI(commandName: "x-gateway-reader", surface: .read)
    let writeCli = XGatewayCLI(commandName: "x-gateway-writer", surface: .write)

    try assertMCPParitySchema(readCli: readCli)
    try assertMCPParityReadAuth(readCli: readCli)
    try assertOpenAPIParityReadAuth(readCli: readCli)
    try assertMCPParityBookmarkAuth(readCli: readCli, writeCli: writeCli)
    try assertMCPParityWriteAuth(writeCli: writeCli)
    try assertMCPParityCapabilities(readCli: readCli, writeCli: writeCli)
    try assertArticleRequestBuilder()
}

private func assertMCPParitySchema(readCli: XGatewayCLI) throws {
    let schema = readCli.run(arguments: ["graphql", "schema"], environment: [:])
    try assert(schema.exitCode == 0, "schema command should succeed for MCP parity smoke tests")
    try assert(schema.stdout.contains("user(id: ID!): AccountProfile!"), "schema should expose user lookup by id")
    try assert(schema.stdout.contains("userByUsername(username: String!): AccountProfile!"), "schema should expose user lookup by username")
    try assert(schema.stdout.contains("users(ids: [ID!]!): UserPage!"), "schema should expose batch user lookup")
    try assert(schema.stdout.contains("usersByUsernames(usernames: [String!]!): UserPage!"), "schema should expose batch username lookup")
    try assert(schema.stdout.contains("followers(userId: ID!"), "schema should expose follower user lists")
    try assert(schema.stdout.contains("following(userId: ID!"), "schema should expose following user lists")
    try assert(schema.stdout.contains("posts(ids: [ID!]!"), "schema should expose batch post lookup")
    try assert(schema.stdout.contains("likedPosts(userId: ID!"), "schema should expose liked post listing")
    try assert(schema.stdout.contains("postLikingUsers(postId: ID!"), "schema should expose post liking users")
    try assert(schema.stdout.contains("postRepostingUsers(postId: ID!"), "schema should expose post reposting users")
    try assert(schema.stdout.contains("postQuotes(postId: ID!"), "schema should expose quoted posts")
    try assert(schema.stdout.contains("searchAllPosts("), "schema should expose full-archive post search")
    try assert(schema.stdout.contains("searchUsers(query: String!"), "schema should expose user search")
    try assert(schema.stdout.contains("searchNews(query: String!"), "schema should expose news search")
    try assert(schema.stdout.contains("news(id: ID!): NewsStory!"), "schema should expose news lookup")
    try assert(schema.stdout.contains("trendsByWoeid(woeid: Int!"), "schema should expose trends by WOEID")
    try assert(schema.stdout.contains("recentPostCounts(query: String!"), "schema should expose recent post counts")
    try assert(schema.stdout.contains("bookmarks(maxResults: Int"), "schema should expose bookmark listing")
    try assert(schema.stdout.contains("bookmarkFolders(maxResults: Int"), "schema should expose bookmark folders")
    try assert(schema.stdout.contains("bookmarksByFolder(folderId: ID!"), "schema should expose bookmark folder posts")
    try assert(schema.stdout.contains("mutedUsers(userId: ID!"), "schema should expose muted user listing")
    try assert(schema.stdout.contains("blockedUsers(userId: ID!"), "schema should expose blocked user listing")
    try assert(schema.stdout.contains("ownedLists(userId: ID!"), "schema should expose owned lists")
    try assert(schema.stdout.contains("pinnedLists(userId: ID!): ListPage!"), "schema should expose non-paged pinned lists")
    try assert(schema.stdout.contains("listPosts(listId: ID!"), "schema should expose list posts")
    try assert(schema.stdout.contains("dmEvents(maxResults: Int"), "schema should expose DM event listing")
    try assert(schema.stdout.contains("dmConversationEvents(participantId: ID!"), "schema should expose one-to-one DM event listing")
    try assert(schema.stdout.contains("bookmarkPost(postId: ID!): BookmarkResult!"), "schema should expose bookmark creation")
    try assert(schema.stdout.contains("removeBookmark(postId: ID!): BookmarkResult!"), "schema should expose bookmark removal")
    try assert(schema.stdout.contains("likePost(postId: ID!): LikeResult!"), "schema should expose like creation")
    try assert(schema.stdout.contains("followUser(targetUserId: ID!): FollowResult!"), "schema should expose follow creation")
    try assert(schema.stdout.contains("createList(name: String!"), "schema should expose List creation")
    try assert(schema.stdout.contains("createDirectMessage(participantId: ID!, text: String!, attachments:"), "schema should expose one-to-one DM attachments")
    try assert(schema.stdout.contains("createArticleDraft(title: String!"), "schema should expose Article draft creation")
    try assert(schema.stdout.contains("publishArticle(articleId: ID!): ArticlePublishResult!"), "schema should expose Article publishing")
    try assert(schema.stdout.contains("complianceJobs(type: String"), "schema should expose compliance job listing")
    try assert(schema.stdout.contains("communitiesSearch(query: String!"), "schema should expose Community search")
    try assert(schema.stdout.contains("postAnalytics(postIds: [ID!]!"), "schema should expose post analytics")
    try assert(schema.stdout.contains("postReposts(postId: ID!"), "schema should expose post repost reads")
    try assert(schema.stdout.contains("media(mediaKeys: [String!]!): OpenAPIResult!"), "schema should expose media lookup")
    try assert(schema.stdout.contains("insights28hr(postIds: [ID!]!"), "schema should expose 28-hour insights")
    try assert(schema.stdout.contains("webhooks: OpenAPIResult!"), "schema should expose webhook listing")
    try assert(schema.stdout.contains("sendEncryptedChatMessage(id: ID!"), "schema should expose encrypted Chat send primitive")
    try assert(schema.stdout.contains("addUserPublicKey("), "schema should expose user public key registration")
    try assert(schema.stdout.contains("initializeChatMediaUpload("), "schema should expose Chat media upload initialization")
    try assert(schema.stdout.contains("uploadMedia(filePath: String!"), "schema should expose one-shot media upload")
    try assert(schema.stdout.contains("appendMediaUpload(mediaId: ID!"), "schema should expose media upload append")
    try assert(schema.stdout.contains("appendChatMediaUpload(id: ID!"), "schema should expose Chat media upload append")
    try assert(schema.stdout.contains("downloadChatMedia(id: ID!"), "schema should expose Chat media download")
    try assert(schema.stdout.contains("downloadDirectMessageMedia(dmId: ID!"), "schema should expose DM media download")
    try assert(schema.stdout.contains("type OpenAPIResult"), "schema should expose raw OpenAPI result envelope")
    try assert(schema.stdout.contains("type PostCountPage"), "schema should expose post count result type")
    try assert(schema.stdout.contains("type UserPage"), "schema should expose user page result type")
    try assert(schema.stdout.contains("type NewsPage"), "schema should expose news page result type")
    try assert(schema.stdout.contains("type TrendPage"), "schema should expose trend page result type")
    try assert(schema.stdout.contains("type BookmarkFolderPage"), "schema should expose bookmark folder page result type")
    try assert(schema.stdout.contains("type ListPage"), "schema should expose List page result type")
    try assert(schema.stdout.contains("type DirectMessageEventPage"), "schema should expose DM event page result type")
}

private func assertMCPParityReadAuth(readCli: XGatewayCLI) throws {
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ users(ids: [\"123\", \"456\"]) { users { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "users"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ usersByUsernames(usernames: [\"xdev\"]) { users { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "usersByUsernames"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ posts(ids: [\"123\"]) { posts { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "posts"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ likedPosts(userId: \"123\", maxResults: 10) { posts { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "likedPosts"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ postLikingUsers(postId: \"123\", maxResults: 10) { users { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "postLikingUsers"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ postRepostingUsers(postId: \"123\", maxResults: 10) { users { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "postRepostingUsers"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ postQuotes(postId: \"123\", maxResults: 10) { posts { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "postQuotes"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ searchAllPosts(query: \"swift\", maxResults: 10) { posts { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "searchAllPosts"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ searchUsers(query: \"xdev\", maxResults: 10) { users { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "searchUsers"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ followers(userId: \"123\", maxResults: 10) { users { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "followers"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ following(userId: \"123\", maxResults: 10) { users { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "following"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ searchNews(query: \"markets\") { stories { id name } } }", "--json"],
            environment: [:]
        ),
        fieldName: "searchNews"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: [
                "graphql",
                "query",
                "{ searchNews(query: \"markets\", maxResults: 100, maxAgeHours: 720) { stories { id name } } }",
                "--json"
            ],
            environment: [:]
        ),
        fieldName: "searchNews"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: [
                "graphql",
                "query",
                "{ searchNews(query: \"markets\", maxResults: 1, maxAgeHours: 1) { stories { id name } } }",
                "--json"
            ],
            environment: [:]
        ),
        fieldName: "searchNews"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ trendsByWoeid(woeid: 1) { trends { name } } }", "--json"],
            environment: [:]
        ),
        fieldName: "trendsByWoeid"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ mutedUsers(userId: \"123\", maxResults: 10) { users { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "mutedUsers"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ blockedUsers(userId: \"123\", maxResults: 10) { users { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "blockedUsers"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ ownedLists(userId: \"123\", maxResults: 10) { lists { id name } } }", "--json"],
            environment: [:]
        ),
        fieldName: "ownedLists"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ pinnedLists(userId: \"123\") { lists { id name } } }", "--json"],
            environment: [:]
        ),
        fieldName: "pinnedLists"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ listPosts(listId: \"123\", maxResults: 10) { posts { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "listPosts"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ dmEvents(maxResults: 10, eventTypes: [\"MessageCreate\"]) { events { id } } }", "--json"],
            environment: [:]
        ),
        fieldName: "dmEvents"
    )
    let countsInvalidGranularity = readCli.run(
        arguments: ["graphql", "query", "{ recentPostCounts(query: \"swift\", granularity: \"week\") { totalPostCount } }", "--json"],
        environment: [:]
    )
    try assert(countsInvalidGranularity.exitCode == 2, "recentPostCounts should validate granularity")
    try assert(countsInvalidGranularity.stderr.contains("granularity"), "recentPostCounts granularity validation should name the argument")

    let searchAllInvalidSort = readCli.run(
        arguments: ["graphql", "query", "{ searchAllPosts(query: \"swift\", sortOrder: \"popular\") { posts { id } } }", "--json"],
        environment: [:]
    )
    try assert(searchAllInvalidSort.exitCode == 2, "searchAllPosts should validate sortOrder")
    try assert(searchAllInvalidSort.stderr.contains("sortOrder"), "searchAllPosts sortOrder validation should name the argument")

    let dmInvalidEventType = readCli.run(
        arguments: ["graphql", "query", "{ dmEvents(eventTypes: [\"BadType\"]) { events { id } } }", "--json"],
        environment: [:]
    )
    try assert(dmInvalidEventType.exitCode == 2, "dmEvents should validate eventTypes")
    try assert(dmInvalidEventType.stderr.contains("eventTypes"), "dmEvents eventTypes validation should name the argument")

    let pinnedListsRejectsPagination = readCli.run(
        arguments: ["graphql", "query", "{ pinnedLists(userId: \"123\", maxResults: 10) { lists { id } } }", "--json"],
        environment: [:]
    )
    try assert(pinnedListsRejectsPagination.exitCode == 2, "pinnedLists should reject unsupported pagination arguments")
    try assert(pinnedListsRejectsPagination.stderr.contains("maxResults"), "pinnedLists pagination validation should name the argument")
}

private func assertOpenAPIParityReadAuth(readCli: XGatewayCLI) throws {
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ complianceJobs(type: \"tweets\") { ok payload } }", "--json"],
            environment: [:]
        ),
        fieldName: "complianceJobs"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: [
                "graphql",
                "query",
                "{ postAnalytics(postIds: [\"123\"], startTime: \"2026-01-01T00:00:00Z\", endTime: \"2026-01-02T00:00:00Z\", granularity: \"day\") { ok payload } }",
                "--json"
            ],
            environment: [:]
        ),
        fieldName: "postAnalytics"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ communitiesSearch(query: \"swift\") { ok payload } }", "--json"],
            environment: [:]
        ),
        fieldName: "communitiesSearch"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: ["graphql", "query", "{ postReposts(postId: \"123\") { ok payload } }", "--json"],
            environment: [:]
        ),
        fieldName: "postReposts"
    )
    try assertAuthMissing(
        readCli.run(
            arguments: [
                "graphql",
                "query",
                "{ downloadDirectMessageMedia(dmId: \"1\", mediaId: \"2\", resourceId: \"image.jpg\", outputPath: \"/tmp/x-gateway-dm-media-test.jpg\") { ok payload } }",
                "--json"
            ],
            environment: [:]
        ),
        fieldName: "downloadDirectMessageMedia"
    )
}

private func assertMCPParityBookmarkAuth(readCli: XGatewayCLI, writeCli: XGatewayCLI) throws {
    try assertAuthMissing(
        readCli.run(arguments: ["graphql", "query", "{ bookmarks(maxResults: 10) { posts { id } } }", "--json"], environment: [:]),
        fieldName: "bookmarks"
    )
    try assertAuthMissing(
        readCli.run(arguments: ["graphql", "query", "{ bookmarkFolders(maxResults: 10) { folders { id name } } }", "--json"], environment: [:]),
        fieldName: "bookmarkFolders"
    )
    try assertAuthMissing(
        readCli.run(arguments: ["graphql", "query", "{ bookmarksByFolder(folderId: \"123\") { posts { id } } }", "--json"], environment: [:]),
        fieldName: "bookmarksByFolder"
    )
    try assertAuthMissing(
        writeCli.run(arguments: ["graphql", "query", "mutation { bookmarkPost(postId: \"123\") { id bookmarked } }", "--json"], environment: [:]),
        fieldName: "bookmarkPost"
    )
    try assertAuthMissing(
        writeCli.run(arguments: ["graphql", "query", "mutation { removeBookmark(postId: \"123\") { id bookmarked } }", "--json"], environment: [:]),
        fieldName: "removeBookmark"
    )

    let oauth1OnlyEnvironment = [
        "X_GW_CONSUMER_KEY": "consumer-key",
        "X_GW_CONSUMER_SECRET": "consumer-secret",
        "X_GW_ACCESS_TOKEN": "access-token",
        "X_GW_ACCESS_TOKEN_SECRET": "access-token-secret"
    ]
    try assertOAuth1OnlyBookmarkRejection(
        readCli.run(arguments: ["graphql", "query", "{ bookmarks(maxResults: 10) { posts { id } } }", "--json"], environment: oauth1OnlyEnvironment),
        fieldName: "bookmarks"
    )
    try assertOAuth1OnlyBookmarkRejection(
        readCli.run(arguments: ["graphql", "query", "{ bookmarkFolders(maxResults: 10) { folders { id name } } }", "--json"], environment: oauth1OnlyEnvironment),
        fieldName: "bookmarkFolders"
    )
    try assertOAuth1OnlyBookmarkRejection(
        readCli.run(arguments: ["graphql", "query", "{ bookmarksByFolder(folderId: \"123\") { posts { id } } }", "--json"], environment: oauth1OnlyEnvironment),
        fieldName: "bookmarksByFolder"
    )
    try assertOAuth1OnlyBookmarkRejection(
        writeCli.run(arguments: ["graphql", "query", "mutation { bookmarkPost(postId: \"123\") { id bookmarked } }", "--json"], environment: oauth1OnlyEnvironment),
        fieldName: "bookmarkPost"
    )
    try assertOAuth1OnlyBookmarkRejection(
        writeCli.run(arguments: ["graphql", "query", "mutation { removeBookmark(postId: \"123\") { id bookmarked } }", "--json"], environment: oauth1OnlyEnvironment),
        fieldName: "removeBookmark"
    )
}

private func assertMCPParityWriteAuth(writeCli: XGatewayCLI) throws {
    try assertAuthMissing(
        writeCli.run(
            arguments: ["graphql", "query", "mutation { createArticleDraft(title: \"Draft\", text: \"Body\") { id title } }", "--json"],
            environment: [:]
        ),
        fieldName: "createArticleDraft"
    )
    try assertAuthMissing(
        writeCli.run(
            arguments: ["graphql", "query", "mutation { publishArticle(articleId: \"123\") { postId } }", "--json"],
            environment: [:]
        ),
        fieldName: "publishArticle"
    )
    try assertAuthMissing(
        writeCli.run(
            arguments: ["graphql", "query", "mutation { likePost(postId: \"123\") { id liked } }", "--json"],
            environment: [:]
        ),
        fieldName: "likePost"
    )
    try assertAuthMissing(
        writeCli.run(
            arguments: ["graphql", "query", "mutation { followUser(targetUserId: \"123\") { id following } }", "--json"],
            environment: [:]
        ),
        fieldName: "followUser"
    )
    try assertAuthMissing(
        writeCli.run(
            arguments: ["graphql", "query", "mutation { createList(name: \"x-gateway-test\") { id name } }", "--json"],
            environment: [:]
        ),
        fieldName: "createList"
    )
    try assertAuthMissing(
        writeCli.run(
            arguments: ["graphql", "query", "mutation { createDirectMessage(participantId: \"123\", text: \"hello\") { id } }", "--json"],
            environment: [:]
        ),
        fieldName: "createDirectMessage"
    )
    try assertAuthMissing(
        writeCli.run(
            arguments: [
                "graphql",
                "query",
                "mutation { createDirectMessage(participantId: \"123\", text: \"hello\", attachments: [{ kind: \"image\", filePath: \"/tmp/x-gateway-missing-dm.gif\" }]) { id } }",
                "--json"
            ],
            environment: [:]
        ),
        fieldName: "createDirectMessage"
    )
    let dmAttachmentMissingFile = writeCli.run(
        arguments: [
            "graphql",
            "query",
            "mutation { createDirectMessage(participantId: \"123\", text: \"hello\", attachments: [{ kind: \"image\", filePath: \"/tmp/x-gateway-missing-dm.gif\" }]) { id } }",
            "--json"
        ],
        environment: ["X_GW_TOKEN": "token"]
    )
    try assert(dmAttachmentMissingFile.exitCode == 2, "DM attachments should validate local media path before upload")
    try assert(dmAttachmentMissingFile.stderr.contains("filePath"), "DM missing media validation should name filePath")
    try assertAuthMissing(
        writeCli.run(
            arguments: ["graphql", "query", "mutation { createComplianceJob(type: \"tweets\", name: \"test\") { ok payload } }", "--json"],
            environment: [:]
        ),
        fieldName: "createComplianceJob"
    )
    try assertAuthMissing(
        writeCli.run(
            arguments: ["graphql", "query", "mutation { initializeMediaUpload(mediaType: \"image/png\", totalBytes: 10) { ok payload } }", "--json"],
            environment: [:]
        ),
        fieldName: "initializeMediaUpload"
    )
    try assertAuthMissing(
        writeCli.run(
            arguments: ["graphql", "query", "mutation { sendEncryptedChatMessage(id: \"1\", messageId: \"m1\", encodedMessageCreateEvent: \"abc\") { ok payload } }", "--json"],
            environment: [:]
        ),
        fieldName: "sendEncryptedChatMessage"
    )
    try assertAuthMissing(
        writeCli.run(
            arguments: [
                "graphql",
                "query",
                "mutation { addUserPublicKey(userId: \"1\", version: \"1\", publicKey: \"pk\", signingPublicKey: \"spk\") { ok payload } }",
                "--json"
            ],
            environment: [:]
        ),
        fieldName: "addUserPublicKey"
    )
    try assertAuthMissing(
        writeCli.run(
            arguments: [
                "graphql",
                "query",
                "mutation { createEncryptedChatGroupConversation(conversationId: \"c1\", conversationKeyVersion: \"1\", conversationParticipantKeysJSON: \"[]\", groupMembers: [\"1\", \"2\"]) { ok payload } }",
                "--json"
            ],
            environment: [:]
        ),
        fieldName: "createEncryptedChatGroupConversation"
    )
    try assertAuthMissing(
        writeCli.run(
            arguments: [
                "graphql",
                "query",
                "mutation { uploadMedia(filePath: \"/tmp/x-gateway-media-test.png\", mediaCategory: \"tweet_image\") { ok payload } }",
                "--json"
            ],
            environment: [:]
        ),
        fieldName: "uploadMedia"
    )
    try assertAuthMissing(
        writeCli.run(
            arguments: [
                "graphql",
                "query",
                "mutation { appendChatMediaUpload(id: \"session\", conversationId: \"conversation\", mediaHashKey: \"hash\", segmentIndex: 0, filePath: \"/tmp/x-gateway-media-test.png\") { ok payload } }",
                "--json"
            ],
            environment: [:]
        ),
        fieldName: "appendChatMediaUpload"
    )
}

private func assertMCPParityCapabilities(readCli: XGatewayCLI, writeCli: XGatewayCLI) throws {
    let quoteCapability = readCli.run(
        arguments: ["capabilities", "get", "--id", "post.quotes", "--json"],
        environment: [:]
    )
    try assert(quoteCapability.exitCode == 0, "capability metadata should expose post.quotes")
    try assert(quoteCapability.stdout.contains("postQuotes"), "post.quotes capability should name the operation")

    let followersCapability = readCli.run(
        arguments: ["capabilities", "get", "--id", "user.followers", "--json"],
        environment: [:]
    )
    try assert(followersCapability.exitCode == 0, "capability metadata should expose user.followers")
    try assert(followersCapability.stdout.contains("followers"), "user.followers capability should name the operation")

    let followingCapability = readCli.run(
        arguments: ["capabilities", "get", "--id", "user.following", "--json"],
        environment: [:]
    )
    try assert(followingCapability.exitCode == 0, "capability metadata should expose user.following")
    try assert(followingCapability.stdout.contains("following"), "user.following capability should name the operation")

    try assertBearerCapability(
        writeCli.run(arguments: ["capabilities", "get", "--id", "bookmarks.add", "--json"], environment: [:]),
        label: "bookmarks.add"
    )
    try assertBearerCapability(
        writeCli.run(arguments: ["capabilities", "get", "--id", "bookmarks.remove", "--json"], environment: [:]),
        label: "bookmarks.remove"
    )
    try assertBearerCapability(
        readCli.run(arguments: ["capabilities", "get", "--id", "bookmarks.folders.list", "--json"], environment: [:]),
        label: "bookmarks.folders.list"
    )
    try assertBearerCapability(
        readCli.run(arguments: ["capabilities", "get", "--id", "bookmarks.folders.posts", "--json"], environment: [:]),
        label: "bookmarks.folders.posts"
    )
    try assertBearerCapability(
        readCli.run(arguments: ["capabilities", "get", "--id", "lists.owned", "--json"], environment: [:]),
        label: "lists.owned"
    )
    try assertBearerCapability(
        readCli.run(arguments: ["capabilities", "get", "--id", "dm.events", "--json"], environment: [:]),
        label: "dm.events"
    )
    try assertBearerCapability(
        writeCli.run(arguments: ["capabilities", "get", "--id", "post.like", "--json"], environment: [:]),
        label: "post.like"
    )
    try assertBearerCapability(
        writeCli.run(arguments: ["capabilities", "get", "--id", "dm.create", "--json"], environment: [:]),
        label: "dm.create"
    )

    let trendCapability = readCli.run(
        arguments: ["capabilities", "get", "--id", "trends.woeid", "--json"],
        environment: [:]
    )
    try assert(trendCapability.exitCode == 0, "capability metadata should expose trends.woeid")
    try assert(trendCapability.stdout.contains("trendsByWoeid"), "trends.woeid capability should name the operation")

    let articleCapability = writeCli.run(
        arguments: ["capabilities", "get", "--id", "articles.draft.create", "--json"],
        environment: [:]
    )
    try assert(articleCapability.exitCode == 0, "capability metadata should expose articles.draft.create")
    try assert(articleCapability.stdout.contains("createArticleDraft"), "articles.draft.create capability should name the operation")

    try assertBearerCapability(
        readCli.run(arguments: ["capabilities", "get", "--id", "analytics.posts", "--json"], environment: [:]),
        label: "analytics.posts"
    )
    try assertBearerCapability(
        writeCli.run(arguments: ["capabilities", "get", "--id", "media.upload.initialize", "--json"], environment: [:]),
        label: "media.upload.initialize"
    )
    try assertBearerCapability(
        writeCli.run(arguments: ["capabilities", "get", "--id", "chat.messages.encrypted.create", "--json"], environment: [:]),
        label: "chat.messages.encrypted.create"
    )
    try assertBearerCapability(
        writeCli.run(arguments: ["capabilities", "get", "--id", "chat.conversations.keys.initialize", "--json"], environment: [:]),
        label: "chat.conversations.keys.initialize"
    )
    try assertBearerCapability(
        writeCli.run(arguments: ["capabilities", "get", "--id", "chat.group.members.add", "--json"], environment: [:]),
        label: "chat.group.members.add"
    )
    try assertBearerCapability(
        writeCli.run(arguments: ["capabilities", "get", "--id", "chat.conversations.read.mark", "--json"], environment: [:]),
        label: "chat.conversations.read.mark"
    )
    try assertBearerCapability(
        writeCli.run(arguments: ["capabilities", "get", "--id", "chat.conversations.typing.send", "--json"], environment: [:]),
        label: "chat.conversations.typing.send"
    )
    try assertBearerCapability(
        writeCli.run(arguments: ["capabilities", "get", "--id", "activity.subscriptions.delete.bulk", "--json"], environment: [:]),
        label: "activity.subscriptions.delete.bulk"
    )
    try assertBearerCapability(
        writeCli.run(arguments: ["capabilities", "get", "--id", "media.upload.append", "--json"], environment: [:]),
        label: "media.upload.append"
    )
    try assertBearerCapability(
        readCli.run(arguments: ["capabilities", "get", "--id", "dm.media.download", "--json"], environment: [:]),
        label: "dm.media.download"
    )
}

private func assertAuthMissing(_ result: XGatewayCommandResult, fieldName: String) throws {
    try assert(result.exitCode == 3, "\(fieldName) should reach auth validation")
    try assert(result.stderr.contains("\(fieldName) requires X_GW_TOKEN"), "\(fieldName) should report missing auth")
}

private func assertOAuth1OnlyBookmarkRejection(_ result: XGatewayCommandResult, fieldName: String) throws {
    try assert(result.exitCode == 3, "\(fieldName) should reject OAuth1-only credentials")
    try assert(result.stderr.contains("\(fieldName) requires X_GW_TOKEN"), "\(fieldName) should require bearer")
    try assert(result.stderr.contains("OAuth1 credentials are not supported"), "\(fieldName) should not accept OAuth1")
}

private func assertBearerCapability(_ result: XGatewayCommandResult, label: String) throws {
    try assert(result.exitCode == 0, "capability metadata should expose \(label)")
    try assert(result.stdout.contains("swift-bearer-baseline"), "\(label) should advertise bearer-only routing")
}

private func assertArticleRequestBuilder() throws {
    try assert(XGatewayArticleRequestBuilder.apiHost == "api.x.com", "Article endpoints should use api.x.com")
    let body = XGatewayArticleRequestBuilder.draftBody(title: "Draft", text: "Body")
    try assert(body["title"] as? String == "Draft", "Article draft body should include title")
    let contentState = body["content_state"] as? [String: Any]
    let blocks = contentState?["blocks"] as? [[String: Any]]
    let block = blocks?.first
    try assert(block?["text"] as? String == "Body", "Article draft block should include text")
    try assert(block?["type"] as? String == "unstyled", "Article draft block should include type")
    try assert(block?["inline_style_ranges"] != nil, "Article draft block should include inline style ranges")
    try assert(block?["entity_ranges"] != nil, "Article draft block should include entity ranges")
    try assert(contentState?["entities"] != nil, "Article draft content_state should include entities")
}
