import XCTest
@testable import XGatewayCore

final class CapabilityCoverageTests: XCTestCase {
    func testAllAdvertisedCapabilitiesAreSchemaBackedAndReachAuthValidation() throws {
        let capabilities = capabilityRows()
        let ids = capabilities.compactMap { $0["id"] as? String }
        XCTAssertEqual(ids.count, Set(ids).count, "capability ids must be unique")

        let operations = capabilities.compactMap { $0["operation"] as? String }
        let documents = capabilityAuthValidationDocuments()
        XCTAssertEqual(
            Set(operations).subtracting(documents.keys).sorted(),
            [],
            "every advertised capability operation should have a deterministic routing test"
        )

        let readCli = XGatewayCLI(commandName: "x-gateway-reader", surface: .read)
        let writeCli = XGatewayCLI(commandName: "x-gateway-writer", surface: .write)
        let schema = readCli.run(arguments: ["graphql", "schema"], environment: [:])
        XCTAssertEqual(schema.exitCode, 0)

        for row in capabilities {
            let operation = try XCTUnwrap(row["operation"] as? String)
            XCTAssertTrue(
                operation == "Post.replies" || schema.stdout.contains(operation),
                "\(operation) should be present in the public schema"
            )

            let access = try XCTUnwrap(row["access"] as? String)
            let document = try XCTUnwrap(documents[operation])
            let cli = access == "read" ? readCli : writeCli
            let result = cli.run(arguments: ["graphql", "query", document, "--json"], environment: [:])
            XCTAssertEqual(result.exitCode, 3, "\(operation) should route to auth validation")
            XCTAssertTrue(result.stderr.contains("X_GW_TOKEN"), "\(operation) should name bearer-token auth")
        }
    }
}

private func capabilityAuthValidationDocuments() -> [String: String] {
    [
        "accountMe": "{ accountMe { id } }",
        "user": "{ user(id: \"123\") { id } }",
        "userByUsername": "{ userByUsername(username: \"xdev\") { id } }",
        "users": "{ users(ids: [\"123\"]) { users { id } } }",
        "usersByUsernames": "{ usersByUsernames(usernames: [\"xdev\"]) { users { id } } }",
        "followers": "{ followers(userId: \"123\", maxResults: 10) { users { id } } }",
        "following": "{ following(userId: \"123\", maxResults: 10) { users { id } } }",
        "mutedUsers": "{ mutedUsers(userId: \"123\", maxResults: 10) { users { id } } }",
        "blockedUsers": "{ blockedUsers(userId: \"123\", maxResults: 10) { users { id } } }",
        "apiUsage": "{ apiUsage(days: 1) { projectId } }",
        "followingTimeline": "{ followingTimeline(maxResults: 10) { posts { id } } }",
        "post": "{ post(id: \"123\") { id } }",
        "posts": "{ posts(ids: [\"123\"]) { posts { id } } }",
        "likedPosts": "{ likedPosts(userId: \"123\", maxResults: 10) { posts { id } } }",
        "Post.replies": "{ post(id: \"123\") { replies(maxResults: 10) { pageInfo { resultCount } } } }",
        "postLikingUsers": "{ postLikingUsers(postId: \"123\", maxResults: 10) { users { id } } }",
        "postRepostingUsers": "{ postRepostingUsers(postId: \"123\", maxResults: 10) { users { id } } }",
        "postQuotes": "{ postQuotes(postId: \"123\", maxResults: 10) { posts { id } } }",
        "searchAllPosts": "{ searchAllPosts(query: \"from:xdev\", maxResults: 10) { posts { id } } }",
        "searchUsers": "{ searchUsers(query: \"xdev\", maxResults: 10) { users { id } } }",
        "searchNews": "{ searchNews(query: \"x\", maxResults: 10) { stories { id } } }",
        "news": "{ news(id: \"123\") { id } }",
        "trendsByWoeid": "{ trendsByWoeid(woeid: 1) { trends { name } } }",
        "recentPostCounts": "{ recentPostCounts(query: \"from:xdev\") { totalPostCount } }",
        "bookmarks": "{ bookmarks(maxResults: 10) { posts { id } } }",
        "bookmarkFolders": "{ bookmarkFolders(maxResults: 10) { folders { id } } }",
        "bookmarksByFolder": "{ bookmarksByFolder(folderId: \"123\") { posts { id } } }",
        "list": "{ list(id: \"123\") { id } }",
        "ownedLists": "{ ownedLists(userId: \"123\", maxResults: 10) { lists { id } } }",
        "followedLists": "{ followedLists(userId: \"123\", maxResults: 10) { lists { id } } }",
        "listMemberships": "{ listMemberships(userId: \"123\", maxResults: 10) { lists { id } } }",
        "pinnedLists": "{ pinnedLists(userId: \"123\") { lists { id } } }",
        "listFollowers": "{ listFollowers(listId: \"123\", maxResults: 10) { users { id } } }",
        "listMembers": "{ listMembers(listId: \"123\", maxResults: 10) { users { id } } }",
        "listPosts": "{ listPosts(listId: \"123\", maxResults: 10) { posts { id } } }",
        "dmEvents": "{ dmEvents(maxResults: 10) { events { id } } }",
        "dmEvent": "{ dmEvent(id: \"123\") { id } }",
        "dmConversationEvents": "{ dmConversationEvents(participantId: \"123\", maxResults: 10) { events { id } } }",
        "dmConversationEventsById": "{ dmConversationEventsById(conversationId: \"1-2\", maxResults: 10) { events { id } } }",
        "searchPosts": "{ searchPosts(query: \"from:xdev\", maxResults: 10) { posts { id } } }",
        "userTimeline": "{ userTimeline(userId: \"123\", maxResults: 10) { posts { id } } }",
        "homeTimeline": "{ homeTimeline(maxResults: 10) { posts { id } } }",
        "mentionsTimeline": "{ mentionsTimeline(userId: \"123\", maxResults: 10) { posts { id } } }",
        "createPost": "mutation { createPost(text: \"test\") { id } }",
        "deletePost": "mutation { deletePost(postId: \"123\") { id deleted } }",
        "replyToPost": "mutation { replyToPost(text: \"test\", replyToPostId: \"123\") { id } }",
        "quotePost": "mutation { quotePost(text: \"test\", quotedPostId: \"123\") { id } }",
        "repostPost": "mutation { repostPost(postId: \"123\") { id reposted } }",
        "unrepostPost": "mutation { unrepostPost(postId: \"123\") { id reposted } }",
        "bookmarkPost": "mutation { bookmarkPost(postId: \"123\") { id bookmarked } }",
        "removeBookmark": "mutation { removeBookmark(postId: \"123\") { id bookmarked } }",
        "likePost": "mutation { likePost(postId: \"123\") { id liked } }",
        "unlikePost": "mutation { unlikePost(postId: \"123\") { id liked } }",
        "followUser": "mutation { followUser(targetUserId: \"123\") { id following } }",
        "unfollowUser": "mutation { unfollowUser(targetUserId: \"123\") { id following } }",
        "muteUser": "mutation { muteUser(targetUserId: \"123\") { id muting } }",
        "unmuteUser": "mutation { unmuteUser(targetUserId: \"123\") { id muting } }",
        "createList": "mutation { createList(name: \"x-gateway-test\", private: true) { id } }",
        "updateList": "mutation { updateList(listId: \"123\", name: \"x-gateway-test\") { id updated } }",
        "deleteList": "mutation { deleteList(listId: \"123\") { id deleted } }",
        "addListMember": "mutation { addListMember(listId: \"123\", userId: \"456\") { id isMember } }",
        "removeListMember": "mutation { removeListMember(listId: \"123\", userId: \"456\") { id isMember } }",
        "followList": "mutation { followList(listId: \"123\") { id following } }",
        "unfollowList": "mutation { unfollowList(listId: \"123\") { id following } }",
        "pinList": "mutation { pinList(listId: \"123\") { id pinned } }",
        "unpinList": "mutation { unpinList(listId: \"123\") { id pinned } }",
        "createDirectMessage": "mutation { createDirectMessage(participantId: \"123\", text: \"test\") { id } }",
        "createDirectMessageConversation": "mutation { createDirectMessageConversation(participantIds: [\"123\", \"456\"], text: \"test\") { id } }",
        "createDirectMessageInConversation": "mutation { createDirectMessageInConversation(conversationId: \"1-2\", text: \"test\") { id } }",
        "deleteDirectMessage": "mutation { deleteDirectMessage(eventId: \"123\") { id deleted } }",
        "createArticleDraft": "mutation { createArticleDraft(title: \"Draft\", text: \"Body\") { id } }",
        "publishArticle": "mutation { publishArticle(articleId: \"123\") { postId } }",
        "complianceJobs": "{ complianceJobs(type: \"tweets\") { ok payload } }",
        "complianceJob": "{ complianceJob(id: \"123\") { ok payload } }",
        "createComplianceJob": "mutation { createComplianceJob(type: \"tweets\", name: \"test\") { ok payload } }",
        "communitiesSearch": "{ communitiesSearch(query: \"swift\", maxResults: 10) { ok payload } }",
        "community": "{ community(id: \"123\") { ok payload } }",
        "communityNotesWritten": "{ communityNotesWritten(testMode: true, maxResults: 10) { ok payload } }",
        "communityPostsEligibleForNotes": "{ communityPostsEligibleForNotes(testMode: true, maxResults: 10) { ok payload } }",
        "communityNote": "{ communityNote(id: \"123\") { ok payload } }",
        "createCommunityNote": "mutation { createCommunityNote(postId: \"123\", classification: \"helpful\", text: \"test\", testMode: true) { ok payload } }",
        "deleteCommunityNote": "mutation { deleteCommunityNote(id: \"123\") { ok payload } }",
        "evaluateCommunityNote": "mutation { evaluateCommunityNote(postId: \"123\", noteText: \"test\") { ok payload } }",
        "postAnalytics": "{ postAnalytics(postIds: [\"123\"], startTime: \"2026-01-01T00:00:00Z\", endTime: \"2026-01-02T00:00:00Z\", granularity: \"day\") { ok payload } }",
        "postReposts": "{ postReposts(postId: \"123\", maxResults: 10) { ok payload } }",
        "mediaAnalytics": "{ mediaAnalytics(mediaKeys: [\"3_123\"], startTime: \"2026-01-01T00:00:00Z\", endTime: \"2026-01-02T00:00:00Z\", granularity: \"day\") { ok payload } }",
        "insights28hr": "{ insights28hr(postIds: [\"123\"], granularity: \"hour\", requestedMetrics: [\"Impressions\"]) { ok payload } }",
        "insightsHistorical": "{ insightsHistorical(postIds: [\"123\"], startTime: \"2026-01-01T00:00:00Z\", " +
            "endTime: \"2026-01-02T00:00:00Z\", granularity: \"day\", requestedMetrics: [\"Impressions\"]) { ok payload } }",
        "media": "{ media(mediaKeys: [\"3_123\"]) { ok payload } }",
        "mediaByKey": "{ mediaByKey(mediaKey: \"3_123\") { ok payload } }",
        "mediaUploadStatus": "{ mediaUploadStatus(mediaId: \"123\") { ok payload } }",
        "uploadMedia": "mutation { uploadMedia(filePath: \"/tmp/x-gateway-test.jpg\", mediaCategory: \"tweet_image\") { ok payload } }",
        "initializeMediaUpload": "mutation { initializeMediaUpload(mediaType: \"image/jpeg\", totalBytes: 1) { ok payload } }",
        "appendMediaUpload": "mutation { appendMediaUpload(mediaId: \"123\", segmentIndex: 0, filePath: \"/tmp/x-gateway-test.jpg\") { ok payload } }",
        "finalizeMediaUpload": "mutation { finalizeMediaUpload(mediaId: \"123\") { ok payload } }",
        "createMediaMetadata": "mutation { createMediaMetadata(mediaId: \"123\", altText: \"test\") { ok payload } }",
        "createMediaSubtitles": "mutation { createMediaSubtitles(mediaId: \"123\", languageCode: \"en\", displayName: \"English\", filePath: \"/tmp/x-gateway-test.srt\") { ok payload } }",
        "deleteMediaSubtitles": "mutation { deleteMediaSubtitles(mediaId: \"123\", languageCode: \"en\") { ok payload } }",
        "allPostCounts": "{ allPostCounts(query: \"from:xdev\") { ok payload } }",
        "hideReply": "mutation { hideReply(postId: \"123\", hidden: true) { ok payload } }",
        "personalizedTrends": "{ personalizedTrends { ok payload } }",
        "publicKeys": "{ publicKeys(userIds: [\"123\"]) { ok payload } }",
        "userPublicKeys": "{ userPublicKeys(userId: \"123\") { ok payload } }",
        "addUserPublicKey": "mutation { addUserPublicKey(userId: \"123\", version: \"1\", publicKey: \"pk\", signingPublicKey: \"spk\") { ok payload } }",
        "userAffiliates": "{ userAffiliates(userId: \"123\", maxResults: 10) { ok payload } }",
        "repostsOfMe": "{ repostsOfMe(maxResults: 10) { ok payload } }",
        "blockDirectMessages": "mutation { blockDirectMessages(userId: \"123\") { ok payload } }",
        "unblockDirectMessages": "mutation { unblockDirectMessages(userId: \"123\") { ok payload } }",
        "webhooks": "{ webhooks { ok payload } }",
        "createWebhook": "mutation { createWebhook(url: \"https://example.com/webhook\") { ok payload } }",
        "deleteWebhook": "mutation { deleteWebhook(webhookId: \"123\") { ok payload } }",
        "validateWebhook": "mutation { validateWebhook(webhookId: \"123\") { ok payload } }",
        "replayWebhook": "mutation { replayWebhook(webhookId: \"123\", fromDate: \"2026-01-01T00:00:00Z\", toDate: \"2026-01-02T00:00:00Z\") { ok payload } }",
        "activitySubscriptions": "{ activitySubscriptions { ok payload } }",
        "createActivitySubscription": "mutation { createActivitySubscription(eventType: \"TweetCreate\", filter: \"from:xdev\") { ok payload } }",
        "updateActivitySubscription": "mutation { updateActivitySubscription(subscriptionId: \"123\", eventType: \"TweetCreate\") { ok payload } }",
        "deleteActivitySubscription": "mutation { deleteActivitySubscription(subscriptionId: \"123\") { ok payload } }",
        "deleteActivitySubscriptions": "mutation { deleteActivitySubscriptions(subscriptionIds: [\"123\"]) { ok payload } }",
        "openAPISpec": "{ openAPISpec { ok payload } }",
        "accountActivitySubscriptionCount": "{ accountActivitySubscriptionCount { ok payload } }",
        "accountActivitySubscriptions": "{ accountActivitySubscriptions(webhookId: \"123\") { ok payload } }",
        "validateAccountActivitySubscription": "{ validateAccountActivitySubscription(webhookId: \"123\") { ok payload } }",
        "createAccountActivitySubscription": "mutation { createAccountActivitySubscription(webhookId: \"123\") { ok payload } }",
        "deleteAccountActivitySubscription": "mutation { deleteAccountActivitySubscription(webhookId: \"123\", userId: \"456\") { ok payload } }",
        "chatConversations": "{ chatConversations(maxResults: 10) { ok payload } }",
        "chatConversation": "{ chatConversation(id: \"123\") { ok payload } }",
        "chatConversationEvents": "{ chatConversationEvents(id: \"123\", maxResults: 10) { ok payload } }",
        "spaces": "{ spaces(ids: [\"1SLjjRYNejbKM\"]) { spaces { id } } }",
        "spacesByCreatorIds": "{ spacesByCreatorIds(userIds: [\"123\"]) { spaces { id } } }",
        "searchSpaces": "{ searchSpaces(query: \"swift\", maxResults: 10) { spaces { id } } }",
        "space": "{ space(id: \"1SLjjRYNejbKM\") { id } }",
        "spaceBuyers": "{ spaceBuyers(id: \"1SLjjRYNejbKM\", maxResults: 10) { users { id } } }",
        "spacePosts": "{ spacePosts(id: \"1SLjjRYNejbKM\", maxResults: 10) { posts { id } } }",
        "streamRules": "{ streamRules(maxResults: 10) { rules { id } } }",
        "streamRuleCounts": "{ streamRuleCounts { ok payload } }",
        "updateStreamRules": #"mutation { updateStreamRules(addJSON: "[{\"value\":\"from:xdev\",\"tag\":\"xdev\"}]", dryRun: true) { rules { id } } }"#,
        "initializeChatConversationKeys": "mutation { initializeChatConversationKeys(id: \"123\") { ok payload } }",
        "addChatGroupMembers": "mutation { addChatGroupMembers(id: \"123\", participantIds: [\"456\"]) { ok payload } }",
        "sendEncryptedChatMessage": "mutation { sendEncryptedChatMessage(id: \"123\", messageId: \"m1\", encodedMessageCreateEvent: \"abc\") { ok payload } }",
        "markChatConversationRead": "mutation { markChatConversationRead(id: \"123\") { ok payload } }",
        "sendChatTypingIndicator": "mutation { sendChatTypingIndicator(id: \"123\") { ok payload } }",
        "createEncryptedChatGroupConversation": #"mutation { createEncryptedChatGroupConversation(conversationId: "123", "# +
            #"conversationKeyVersion: "1", conversationParticipantKeysJSON: "{\"keys\":[]}", groupMembers: ["456"]) { ok payload } }"#,
        "initializeChatGroup": "mutation { initializeChatGroup { ok payload } }",
        "initializeChatMediaUpload": "mutation { initializeChatMediaUpload(conversationId: \"123\", totalBytes: 1) { ok payload } }",
        "appendChatMediaUpload": "mutation { appendChatMediaUpload(id: \"123\", conversationId: \"456\", mediaHashKey: \"hash\", segmentIndex: 0, filePath: \"/tmp/x-gateway-test.jpg\") { ok payload } }",
        "finalizeChatMediaUpload": "mutation { finalizeChatMediaUpload(id: \"123\", conversationId: \"456\", mediaHashKey: \"hash\") { ok payload } }",
        "downloadChatMedia": "{ downloadChatMedia(id: \"123\", mediaHashKey: \"hash\", outputPath: \"/tmp/x-gateway-chat-media\") { ok payload } }",
        "downloadDirectMessageMedia": "{ downloadDirectMessageMedia(dmId: \"123\", mediaId: \"456\", resourceId: \"image.jpg\", outputPath: \"/tmp/x-gateway-dm-media\") { ok payload } }"
    ]
}
