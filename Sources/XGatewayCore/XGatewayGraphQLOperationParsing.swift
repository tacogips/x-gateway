import Foundation

enum SupportedGraphQLOperation {
    case accountMe
    case apiUsage(days: Int)
    case user(userId: String)
    case userByUsername(username: String)
    case users(ids: [String])
    case usersByUsernames(usernames: [String])
    case followers(userId: String, maxResults: Int, paginationToken: String?)
    case following(userId: String, maxResults: Int, paginationToken: String?)
    case post(postId: String, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case posts(ids: [String], readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case likedPosts(userId: String, maxResults: Int, paginationToken: String?, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case postLikingUsers(postId: String, maxResults: Int, paginationToken: String?)
    case postRepostingUsers(postId: String, maxResults: Int, paginationToken: String?)
    case postQuotes(postId: String, maxResults: Int, paginationToken: String?, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case searchAllPosts(query: String, options: SearchAllPostsRequestOptions, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case searchUsers(query: String, maxResults: Int, nextToken: String?)
    case searchNews(query: String, maxResults: Int, maxAgeHours: Int)
    case news(id: String)
    case trendsByWoeid(woeid: Int, maxTrends: Int)
    case recentPostCounts(query: String, options: PostCountsRequestOptions)
    case bookmarks(maxResults: Int, paginationToken: String?, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case bookmarkFolders(maxResults: Int, paginationToken: String?)
    case bookmarksByFolder(folderId: String, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case mutedUsers(userId: String, maxResults: Int, paginationToken: String?)
    case blockedUsers(userId: String, maxResults: Int, paginationToken: String?)
    case list(listId: String)
    case ownedLists(userId: String, maxResults: Int, paginationToken: String?)
    case followedLists(userId: String, maxResults: Int, paginationToken: String?)
    case listMemberships(userId: String, maxResults: Int, paginationToken: String?)
    case pinnedLists(userId: String)
    case listFollowers(listId: String, maxResults: Int, paginationToken: String?)
    case listMembers(listId: String, maxResults: Int, paginationToken: String?)
    case listPosts(listId: String, maxResults: Int, paginationToken: String?, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case dmEvents(maxResults: Int, paginationToken: String?, eventTypes: [String]?)
    case dmEvent(eventId: String)
    case dmConversationEvents(participantId: String, maxResults: Int, paginationToken: String?, eventTypes: [String]?)
    case dmConversationEventsById(conversationId: String, maxResults: Int, paginationToken: String?, eventTypes: [String]?)
    case searchPosts(query: String, maxResults: Int, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case homeTimeline(maxResults: Int, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case followingTimeline(maxResults: Int, maxUsers: Int, maxResultsPerUser: Int, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case userTimeline(userId: String, maxResults: Int, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case mentionsTimeline(userId: String, maxResults: Int, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
    case createPost(text: String, attachments: [PostAttachmentInput]?)
    case deletePost(postId: String)
    case replyToPost(text: String, replyToPostId: String, attachments: [PostAttachmentInput]?)
    case quotePost(text: String, quotedPostId: String, attachments: [PostAttachmentInput]?)
    case repostPost(postId: String)
    case unrepostPost(postId: String)
    case bookmarkPost(postId: String)
    case removeBookmark(postId: String)
    case likePost(postId: String)
    case unlikePost(postId: String)
    case followUser(targetUserId: String)
    case unfollowUser(targetUserId: String)
    case muteUser(targetUserId: String)
    case unmuteUser(targetUserId: String)
    case createList(name: String, description: String?, isPrivate: Bool)
    case updateList(listId: String, name: String?, description: String?, isPrivate: Bool?)
    case deleteList(listId: String)
    case addListMember(listId: String, userId: String)
    case removeListMember(listId: String, userId: String)
    case followList(listId: String)
    case unfollowList(listId: String)
    case pinList(listId: String)
    case unpinList(listId: String)
    case createDirectMessage(participantId: String, text: String, attachments: [PostAttachmentInput]?)
    case createDirectMessageInConversation(conversationId: String, text: String, attachments: [PostAttachmentInput]?)
    case createDirectMessageConversation(participantIds: [String], text: String, attachments: [PostAttachmentInput]?)
    case deleteDirectMessage(eventId: String)
    case createArticleDraft(title: String, text: String)
    case publishArticle(articleId: String)
    case openAPIQuery(OpenAPIParityRequest)
    case openAPIMutation(OpenAPIParityRequest)
    case openAPIFileDownload(OpenAPIFileDownloadRequest)
    case openAPIFileUpload(OpenAPIFileUploadRequest)

    var fieldName: String {
        switch self {
        case .accountMe:
            return "accountMe"
        case .apiUsage:
            return "apiUsage"
        case .user:
            return "user"
        case .userByUsername:
            return "userByUsername"
        case .users:
            return "users"
        case .usersByUsernames:
            return "usersByUsernames"
        case .followers:
            return "followers"
        case .following:
            return "following"
        case .post:
            return "post"
        case .posts:
            return "posts"
        case .likedPosts:
            return "likedPosts"
        case .postLikingUsers:
            return "postLikingUsers"
        case .postRepostingUsers:
            return "postRepostingUsers"
        case .postQuotes:
            return "postQuotes"
        case .searchAllPosts:
            return "searchAllPosts"
        case .searchUsers:
            return "searchUsers"
        case .searchNews:
            return "searchNews"
        case .news:
            return "news"
        case .trendsByWoeid:
            return "trendsByWoeid"
        case .recentPostCounts:
            return "recentPostCounts"
        case .bookmarks:
            return "bookmarks"
        case .bookmarkFolders:
            return "bookmarkFolders"
        case .bookmarksByFolder:
            return "bookmarksByFolder"
        case .mutedUsers:
            return "mutedUsers"
        case .blockedUsers:
            return "blockedUsers"
        case .list:
            return "list"
        case .ownedLists:
            return "ownedLists"
        case .followedLists:
            return "followedLists"
        case .listMemberships:
            return "listMemberships"
        case .pinnedLists:
            return "pinnedLists"
        case .listFollowers:
            return "listFollowers"
        case .listMembers:
            return "listMembers"
        case .listPosts:
            return "listPosts"
        case .dmEvents:
            return "dmEvents"
        case .dmEvent:
            return "dmEvent"
        case .dmConversationEvents:
            return "dmConversationEvents"
        case .dmConversationEventsById:
            return "dmConversationEventsById"
        case .searchPosts:
            return "searchPosts"
        case .homeTimeline:
            return "homeTimeline"
        case .followingTimeline:
            return "followingTimeline"
        case .userTimeline:
            return "userTimeline"
        case .mentionsTimeline:
            return "mentionsTimeline"
        case .createPost:
            return "createPost"
        case .deletePost:
            return "deletePost"
        case .replyToPost:
            return "replyToPost"
        case .quotePost:
            return "quotePost"
        case .repostPost:
            return "repostPost"
        case .unrepostPost:
            return "unrepostPost"
        case .bookmarkPost:
            return "bookmarkPost"
        case .removeBookmark:
            return "removeBookmark"
        case .likePost:
            return "likePost"
        case .unlikePost:
            return "unlikePost"
        case .followUser:
            return "followUser"
        case .unfollowUser:
            return "unfollowUser"
        case .muteUser:
            return "muteUser"
        case .unmuteUser:
            return "unmuteUser"
        case .createList:
            return "createList"
        case .updateList:
            return "updateList"
        case .deleteList:
            return "deleteList"
        case .addListMember:
            return "addListMember"
        case .removeListMember:
            return "removeListMember"
        case .followList:
            return "followList"
        case .unfollowList:
            return "unfollowList"
        case .pinList:
            return "pinList"
        case .unpinList:
            return "unpinList"
        case .createDirectMessage:
            return "createDirectMessage"
        case .createDirectMessageInConversation:
            return "createDirectMessageInConversation"
        case .createDirectMessageConversation:
            return "createDirectMessageConversation"
        case .deleteDirectMessage:
            return "deleteDirectMessage"
        case .createArticleDraft:
            return "createArticleDraft"
        case .publishArticle:
            return "publishArticle"
        case .openAPIQuery(let request), .openAPIMutation(let request):
            return request.fieldName
        case .openAPIFileDownload(let request):
            return request.fieldName
        case .openAPIFileUpload(let request):
            return request.fieldName
        }
    }

    var supportsOAuth1: Bool {
        switch self {
        case .apiUsage, .searchAllPosts, .searchUsers, .searchNews, .news, .trendsByWoeid,
             .bookmarks, .bookmarkFolders, .bookmarksByFolder, .bookmarkPost, .removeBookmark,
             .likedPosts, .mutedUsers, .blockedUsers, .likePost, .unlikePost, .followUser,
             .unfollowUser, .muteUser, .unmuteUser, .list, .ownedLists, .followedLists,
             .listMemberships, .pinnedLists, .listFollowers, .listMembers, .listPosts,
             .createList, .updateList, .deleteList, .addListMember, .removeListMember,
             .followList, .unfollowList, .pinList, .unpinList, .dmEvents, .dmEvent,
             .dmConversationEvents, .dmConversationEventsById, .createDirectMessage,
             .createDirectMessageInConversation, .createDirectMessageConversation,
             .deleteDirectMessage, .openAPIQuery, .openAPIMutation, .openAPIFileDownload,
             .openAPIFileUpload:
            return false
        default:
            return true
        }
    }

    var requiresOAuth1: Bool {
        false
    }

    var prefersBearerAuthorization: Bool {
        switch self {
        case .createPost(_, let attachments),
             .replyToPost(_, _, let attachments),
             .quotePost(_, _, let attachments):
            return attachments?.isEmpty == false
        default:
            return false
        }
    }
}

struct PostCountsRequestOptions {
    let startTime: String?
    let endTime: String?
    let sinceId: String?
    let untilId: String?
    let nextToken: String?
    let paginationToken: String?
    let granularity: String
}

struct SearchAllPostsRequestOptions {
    let startTime: String?
    let endTime: String?
    let sinceId: String?
    let untilId: String?
    let nextToken: String?
    let paginationToken: String?
    let sortOrder: String?
    let maxResults: Int
}

struct PostAttachmentInput {
    let kind: String
    let filePath: String
    let altText: String?
}

struct GraphQLRootField {
    let name: String
    let argumentLiteral: String
    let selectionLiteral: String?
}

struct ResolvedGraphQLRootOperation {
    let fieldName: String?
    let argumentLiteral: String
}

let supportedQueryGraphQLFields = [
    "accountMe",
    "apiUsage",
    "user",
    "userByUsername",
    "users",
    "usersByUsernames",
    "followers",
    "following",
    "likedPosts",
    "postLikingUsers",
    "postRepostingUsers",
    "postQuotes",
    "searchAllPosts",
    "searchUsers",
    "searchNews",
    "news",
    "trendsByWoeid",
    "recentPostCounts",
    "bookmarks",
    "bookmarkFolders",
    "bookmarksByFolder",
    "mutedUsers",
    "blockedUsers",
    "list",
    "ownedLists",
    "followedLists",
    "listMemberships",
    "pinnedLists",
    "listFollowers",
    "listMembers",
    "listPosts",
    "dmEvents",
    "dmEvent",
    "dmConversationEvents",
    "dmConversationEventsById",
    "searchPosts",
    "homeTimeline",
    "followingTimeline",
    "userTimeline",
    "mentionsTimeline",
    "post",
    "posts"
] + openAPIParityQueryFields + openAPIFileDownloadFields

let supportedMutationGraphQLFields = [
    "createPost",
    "deletePost",
    "replyToPost",
    "quotePost",
    "unrepostPost",
    "repostPost",
    "bookmarkPost",
    "removeBookmark",
    "likePost",
    "unlikePost",
    "followUser",
    "unfollowUser",
    "muteUser",
    "unmuteUser",
    "createList",
    "updateList",
    "deleteList",
    "addListMember",
    "removeListMember",
    "followList",
    "unfollowList",
    "pinList",
    "unpinList",
    "createDirectMessage",
    "createDirectMessageInConversation",
    "createDirectMessageConversation",
    "deleteDirectMessage",
    "createArticleDraft",
    "publishArticle"
] + openAPIParityMutationFields + openAPIFileUploadFields

private let supportedGraphQLFieldDescription = (supportedQueryGraphQLFields + supportedMutationGraphQLFields)
    .joined(separator: ", ")

private enum SupportedGraphQLFieldArguments {
    static let accountMe = GraphQLArgumentSet.noArguments
    static let apiUsage: Set<String> = ["days"]
    static let user: Set<String> = ["id"]
    static let userByUsername: Set<String> = ["username"]
    static let userConnectionPage: Set<String> = ["userId", "maxResults", "paginationToken"]
    static let post = GraphQLArgumentSet.postReadOptions.union(["id"])
    static let postEngagementUsers: Set<String> = ["postId", "maxResults", "paginationToken"]
    static let postQuotes = GraphQLArgumentSet.pagedPostReadOptions.union(["postId"])
    static let searchAllPosts = GraphQLArgumentSet.pagedPostReadOptions.union([
        "query",
        "startTime",
        "endTime",
        "sinceId",
        "untilId",
        "nextToken",
        "sortOrder"
    ])
    static let searchUsers: Set<String> = ["query", "maxResults", "nextToken"]
    static let searchNews: Set<String> = ["query", "maxResults", "maxAgeHours"]
    static let news: Set<String> = ["id"]
    static let trendsByWoeid: Set<String> = ["woeid", "maxTrends"]
    static let recentPostCounts: Set<String> = [
        "query",
        "startTime",
        "endTime",
        "sinceId",
        "untilId",
        "nextToken",
        "paginationToken",
        "granularity"
    ]
    static let bookmarks = GraphQLArgumentSet.pagedPostReadOptions
    static let bookmarkFolders: Set<String> = ["maxResults", "paginationToken"]
    static let bookmarksByFolder = GraphQLArgumentSet.postReadOptions.union(["folderId"])
    static let searchPosts = GraphQLArgumentSet.pagedPostReadOptions.union(["query"])
    static let timeline = GraphQLArgumentSet.pagedPostReadOptions
    static let followingTimeline = GraphQLArgumentSet.pagedPostReadOptions.union([
        "maxUsers",
        "maxResultsPerUser"
    ])
    static let userTimeline = GraphQLArgumentSet.pagedPostReadOptions.union(["userId"])
    static let createPost: Set<String> = ["text", "attachments"]
    static let deletePost: Set<String> = ["postId"]
    static let replyToPost: Set<String> = ["text", "replyToPostId", "attachments"]
    static let quotePost: Set<String> = ["text", "quotedPostId", "attachments"]
    static let repostPost = deletePost
    static let createArticleDraft: Set<String> = ["title", "text"]
    static let publishArticle: Set<String> = ["articleId"]
}

func parseSupportedOperation(
    document: String,
    operationType: XGatewayGraphQLOperationType
) throws -> SupportedGraphQLOperation {
    let resolvedOperation = try resolveSupportedGraphQLRootOperation(in: document, operationType: operationType)
    let fieldName = resolvedOperation.fieldName
    let arguments = resolvedOperation.argumentLiteral
    switch operationType {
    case .query:
        if fieldName == "accountMe" {
            try validateGraphQLArguments(in: arguments, allowed: SupportedGraphQLFieldArguments.accountMe, fieldName: "accountMe")
            return .accountMe
        }
        if fieldName == "apiUsage" {
            try validateGraphQLArguments(in: arguments, allowed: SupportedGraphQLFieldArguments.apiUsage, fieldName: "apiUsage")
            return .apiUsage(days: try extractOptionalIntArgument("days", from: arguments, defaultValue: 1, minimum: 1, maximum: 90, fieldName: "apiUsage"))
        }
        if let operation = try parseMCPParityQueryOperation(
            fieldName: fieldName,
            arguments: arguments,
            document: document,
            operationType: operationType
        ) {
            return operation
        }
        if let operation = try parseExtendedParityQueryOperation(
            fieldName: fieldName,
            arguments: arguments,
            document: document,
            operationType: operationType
        ) {
            return operation
        }
        if let operation = try parseOpenAPIParityQueryOperation(fieldName: fieldName, arguments: arguments) {
            return operation
        }
        if let operation = try parseOpenAPIFileDownloadOperation(fieldName: fieldName, arguments: arguments) {
            return operation
        }
        if let operation = try parseNativeGraphQLQueryOperation(
            fieldName: fieldName,
            arguments: arguments,
            document: document,
            operationType: operationType
        ) {
            return operation
        }
    case .mutation:
        if let operation = try parseExtendedParityMutationOperation(fieldName: fieldName, arguments: arguments) {
            return operation
        }
        if let operation = try parseOpenAPIParityMutationOperation(fieldName: fieldName, arguments: arguments) {
            return operation
        }
        if let operation = try parseOpenAPIFileUploadOperation(fieldName: fieldName, arguments: arguments) {
            return operation
        }
        if fieldName == "createPost" {
            try validateGraphQLArguments(in: arguments, allowed: SupportedGraphQLFieldArguments.createPost, fieldName: "createPost")
            return .createPost(
                text: try extractStringArgument("text", from: arguments, fieldName: "createPost"),
                attachments: try extractPostAttachmentsIfPresent(from: arguments, fieldName: "createPost")
            )
        }
        if fieldName == "deletePost" {
            try validateGraphQLArguments(in: arguments, allowed: SupportedGraphQLFieldArguments.deletePost, fieldName: "deletePost")
            return .deletePost(postId: try extractStringArgument("postId", from: arguments, fieldName: "deletePost"))
        }
        if fieldName == "replyToPost" {
            try validateGraphQLArguments(in: arguments, allowed: SupportedGraphQLFieldArguments.replyToPost, fieldName: "replyToPost")
            return .replyToPost(
                text: try extractStringArgument("text", from: arguments, fieldName: "replyToPost"),
                replyToPostId: try extractStringArgument("replyToPostId", from: arguments, fieldName: "replyToPost"),
                attachments: try extractPostAttachmentsIfPresent(from: arguments, fieldName: "replyToPost")
            )
        }
        if fieldName == "quotePost" {
            try validateGraphQLArguments(in: arguments, allowed: SupportedGraphQLFieldArguments.quotePost, fieldName: "quotePost")
            return .quotePost(
                text: try extractStringArgument("text", from: arguments, fieldName: "quotePost"),
                quotedPostId: try extractStringArgument("quotedPostId", from: arguments, fieldName: "quotePost"),
                attachments: try extractPostAttachmentsIfPresent(from: arguments, fieldName: "quotePost")
            )
        }
        if fieldName == "unrepostPost" {
            try validateGraphQLArguments(in: arguments, allowed: SupportedGraphQLFieldArguments.repostPost, fieldName: "unrepostPost")
            return .unrepostPost(postId: try extractStringArgument("postId", from: arguments, fieldName: "unrepostPost"))
        }
        if fieldName == "repostPost" {
            try validateGraphQLArguments(in: arguments, allowed: SupportedGraphQLFieldArguments.repostPost, fieldName: "repostPost")
            return .repostPost(postId: try extractStringArgument("postId", from: arguments, fieldName: "repostPost"))
        }
        if fieldName == "bookmarkPost" {
            try validateGraphQLArguments(in: arguments, allowed: SupportedGraphQLFieldArguments.repostPost, fieldName: "bookmarkPost")
            return .bookmarkPost(postId: try extractStringArgument("postId", from: arguments, fieldName: "bookmarkPost"))
        }
        if fieldName == "removeBookmark" {
            try validateGraphQLArguments(in: arguments, allowed: SupportedGraphQLFieldArguments.repostPost, fieldName: "removeBookmark")
            return .removeBookmark(postId: try extractStringArgument("postId", from: arguments, fieldName: "removeBookmark"))
        }
        if fieldName == "createArticleDraft" {
            try validateGraphQLArguments(in: arguments, allowed: SupportedGraphQLFieldArguments.createArticleDraft, fieldName: "createArticleDraft")
            return .createArticleDraft(
                title: try extractStringArgument("title", from: arguments, fieldName: "createArticleDraft"),
                text: try extractStringArgument("text", from: arguments, fieldName: "createArticleDraft")
            )
        }
        if fieldName == "publishArticle" {
            try validateGraphQLArguments(in: arguments, allowed: SupportedGraphQLFieldArguments.publishArticle, fieldName: "publishArticle")
            return .publishArticle(articleId: try extractStringArgument("articleId", from: arguments, fieldName: "publishArticle"))
        }
    }

    throw XGatewayErrorPayload(
        code: .unsupported,
        summary: "Swift GraphQL field is not implemented yet",
        details: "This Swift migration slice supports \(supportedGraphQLFieldDescription).",
        likelyCauses: ["The requested project-owned GraphQL field has not been ported to Swift yet"],
        remediations: [
            "Use one of the Swift-supported project-owned GraphQL fields listed in this error.",
            "Add a reviewed Swift transport adapter before exposing another project-owned GraphQL field."
        ],
        classification: "unsupported",
        retryable: false,
        traceId: nil
    )
}

private func parseNativeGraphQLQueryOperation(
    fieldName: String?,
    arguments: String,
    document: String,
    operationType: XGatewayGraphQLOperationType
) throws -> SupportedGraphQLOperation? {
    if fieldName == "searchPosts" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.searchPosts,
            fieldName: "searchPosts"
        )
        return .searchPosts(
            query: try extractStringArgument("query", from: arguments, fieldName: "searchPosts"),
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 10, maximum: 100, fieldName: "searchPosts"),
            readOptions: try extractPostReadOptions(from: arguments, fieldName: "searchPosts"),
            replyExpansion: try extractReplyExpansion(
                from: document,
                operationType: operationType,
                selectionPath: "searchPosts.posts"
            )
        )
    }
    if fieldName == "homeTimeline" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.timeline,
            fieldName: "homeTimeline"
        )
        return .homeTimeline(
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 5, maximum: 100, fieldName: "homeTimeline"),
            readOptions: try extractPostReadOptions(from: arguments, fieldName: "homeTimeline"),
            replyExpansion: try extractReplyExpansion(
                from: document,
                operationType: operationType,
                selectionPath: "homeTimeline.posts"
            )
        )
    }
    if fieldName == "followingTimeline" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.followingTimeline,
            fieldName: "followingTimeline"
        )
        return .followingTimeline(
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 1, maximum: 100, fieldName: "followingTimeline"),
            maxUsers: try extractOptionalIntArgument("maxUsers", from: arguments, defaultValue: 25, minimum: 1, maximum: 100, fieldName: "followingTimeline"),
            maxResultsPerUser: try extractOptionalIntArgument("maxResultsPerUser", from: arguments, defaultValue: 10, minimum: 5, maximum: 100, fieldName: "followingTimeline"),
            readOptions: try extractPostReadOptions(from: arguments, fieldName: "followingTimeline"),
            replyExpansion: try extractReplyExpansion(
                from: document,
                operationType: operationType,
                selectionPath: "followingTimeline.posts"
            )
        )
    }
    if fieldName == "userTimeline" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.userTimeline,
            fieldName: "userTimeline"
        )
        return .userTimeline(
            userId: try extractStringArgument("userId", from: arguments, fieldName: "userTimeline"),
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 5, maximum: 100, fieldName: "userTimeline"),
            readOptions: try extractPostReadOptions(from: arguments, fieldName: "userTimeline"),
            replyExpansion: try extractReplyExpansion(
                from: document,
                operationType: operationType,
                selectionPath: "userTimeline.posts"
            )
        )
    }
    if fieldName == "mentionsTimeline" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.userTimeline,
            fieldName: "mentionsTimeline"
        )
        return .mentionsTimeline(
            userId: try extractStringArgument("userId", from: arguments, fieldName: "mentionsTimeline"),
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 5, maximum: 100, fieldName: "mentionsTimeline"),
            readOptions: try extractPostReadOptions(from: arguments, fieldName: "mentionsTimeline"),
            replyExpansion: try extractReplyExpansion(
                from: document,
                operationType: operationType,
                selectionPath: "mentionsTimeline.posts"
            )
        )
    }
    if fieldName == "post" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.post,
            fieldName: "post"
        )
        return .post(
            postId: try extractStringArgument("id", from: arguments, fieldName: "post"),
            readOptions: try extractPostReadOptions(from: arguments, fieldName: "post"),
            replyExpansion: try extractReplyExpansion(
                from: document,
                operationType: operationType,
                selectionPath: "post"
            )
        )
    }
    return nil
}

private func parseMCPParityQueryOperation(
    fieldName: String?,
    arguments: String,
    document: String,
    operationType: XGatewayGraphQLOperationType
) throws -> SupportedGraphQLOperation? {
    if fieldName == "user" {
        try validateGraphQLArguments(in: arguments, allowed: SupportedGraphQLFieldArguments.user, fieldName: "user")
        return .user(userId: try extractStringArgument("id", from: arguments, fieldName: "user"))
    }
    if fieldName == "userByUsername" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.userByUsername,
            fieldName: "userByUsername"
        )
        return .userByUsername(username: try extractStringArgument("username", from: arguments, fieldName: "userByUsername"))
    }
    if fieldName == "followers" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.userConnectionPage,
            fieldName: "followers"
        )
        return .followers(
            userId: try extractStringArgument("userId", from: arguments, fieldName: "followers"),
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 100, minimum: 1, maximum: 1_000, fieldName: "followers"),
            paginationToken: try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: "followers")
        )
    }
    if fieldName == "following" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.userConnectionPage,
            fieldName: "following"
        )
        return .following(
            userId: try extractStringArgument("userId", from: arguments, fieldName: "following"),
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 100, minimum: 1, maximum: 1_000, fieldName: "following"),
            paginationToken: try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: "following")
        )
    }
    if fieldName == "postLikingUsers" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.postEngagementUsers,
            fieldName: "postLikingUsers"
        )
        return .postLikingUsers(
            postId: try extractStringArgument("postId", from: arguments, fieldName: "postLikingUsers"),
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 1, maximum: 100, fieldName: "postLikingUsers"),
            paginationToken: try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: "postLikingUsers")
        )
    }
    if fieldName == "postRepostingUsers" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.postEngagementUsers,
            fieldName: "postRepostingUsers"
        )
        return .postRepostingUsers(
            postId: try extractStringArgument("postId", from: arguments, fieldName: "postRepostingUsers"),
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 1, maximum: 100, fieldName: "postRepostingUsers"),
            paginationToken: try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: "postRepostingUsers")
        )
    }
    if fieldName == "postQuotes" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.postQuotes,
            fieldName: "postQuotes"
        )
        return .postQuotes(
            postId: try extractStringArgument("postId", from: arguments, fieldName: "postQuotes"),
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 10, maximum: 100, fieldName: "postQuotes"),
            paginationToken: try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: "postQuotes"),
            readOptions: try extractPostReadOptions(from: arguments, fieldName: "postQuotes"),
            replyExpansion: try extractReplyExpansion(
                from: document,
                operationType: operationType,
                selectionPath: "postQuotes.posts"
            )
        )
    }
    if fieldName == "recentPostCounts" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.recentPostCounts,
            fieldName: "recentPostCounts"
        )
        return .recentPostCounts(
            query: try extractStringArgument("query", from: arguments, fieldName: "recentPostCounts"),
            options: try extractPostCountsRequestOptions(from: arguments, fieldName: "recentPostCounts")
        )
    }
    if fieldName == "searchAllPosts" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.searchAllPosts,
            fieldName: "searchAllPosts"
        )
        return .searchAllPosts(
            query: try extractStringArgument("query", from: arguments, fieldName: "searchAllPosts"),
            options: try extractSearchAllPostsRequestOptions(from: arguments, fieldName: "searchAllPosts"),
            readOptions: try extractPostReadOptions(from: arguments, fieldName: "searchAllPosts"),
            replyExpansion: try extractReplyExpansion(
                from: document,
                operationType: operationType,
                selectionPath: "searchAllPosts.posts"
            )
        )
    }
    if fieldName == "searchUsers" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.searchUsers,
            fieldName: "searchUsers"
        )
        return .searchUsers(
            query: try extractStringArgument("query", from: arguments, fieldName: "searchUsers"),
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 100, minimum: 1, maximum: 100, fieldName: "searchUsers"),
            nextToken: try extractOptionalStringArgument("nextToken", from: arguments, fieldName: "searchUsers")
        )
    }
    if fieldName == "searchNews" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.searchNews,
            fieldName: "searchNews"
        )
        return .searchNews(
            query: try extractStringArgument("query", from: arguments, fieldName: "searchNews"),
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 1, maximum: 100, fieldName: "searchNews"),
            maxAgeHours: try extractOptionalIntArgument("maxAgeHours", from: arguments, defaultValue: 168, minimum: 1, maximum: 720, fieldName: "searchNews")
        )
    }
    if fieldName == "news" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.news,
            fieldName: "news"
        )
        return .news(id: try extractStringArgument("id", from: arguments, fieldName: "news"))
    }
    if fieldName == "trendsByWoeid" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.trendsByWoeid,
            fieldName: "trendsByWoeid"
        )
        return .trendsByWoeid(
            woeid: try extractRequiredIntArgument("woeid", from: arguments, minimum: 1, maximum: Int.max, fieldName: "trendsByWoeid"),
            maxTrends: try extractOptionalIntArgument("maxTrends", from: arguments, defaultValue: 20, minimum: 1, maximum: 50, fieldName: "trendsByWoeid")
        )
    }
    if fieldName == "bookmarks" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.bookmarks,
            fieldName: "bookmarks"
        )
        return .bookmarks(
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 1, maximum: 100, fieldName: "bookmarks"),
            paginationToken: try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: "bookmarks"),
            readOptions: try extractPostReadOptions(from: arguments, fieldName: "bookmarks"),
            replyExpansion: try extractReplyExpansion(
                from: document,
                operationType: operationType,
                selectionPath: "bookmarks.posts"
            )
        )
    }
    if fieldName == "bookmarkFolders" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.bookmarkFolders,
            fieldName: "bookmarkFolders"
        )
        return .bookmarkFolders(
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 1, maximum: 100, fieldName: "bookmarkFolders"),
            paginationToken: try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: "bookmarkFolders")
        )
    }
    if fieldName == "bookmarksByFolder" {
        try validateGraphQLArguments(
            in: arguments,
            allowed: SupportedGraphQLFieldArguments.bookmarksByFolder,
            fieldName: "bookmarksByFolder"
        )
        return .bookmarksByFolder(
            folderId: try extractStringArgument("folderId", from: arguments, fieldName: "bookmarksByFolder"),
            readOptions: try extractPostReadOptions(from: arguments, fieldName: "bookmarksByFolder"),
            replyExpansion: try extractReplyExpansion(
                from: document,
                operationType: operationType,
                selectionPath: "bookmarksByFolder.posts"
            )
        )
    }
    return nil
}

private func extractSearchAllPostsRequestOptions(
    from arguments: String,
    fieldName: String
) throws -> SearchAllPostsRequestOptions {
    let sortOrder = try extractOptionalStringArgument("sortOrder", from: arguments, fieldName: fieldName)
    if let sortOrder,
       !["recency", "relevancy"].contains(sortOrder) {
        throw validation("\(fieldName).sortOrder must be one of: recency, relevancy.")
    }
    return SearchAllPostsRequestOptions(
        startTime: try extractOptionalStringArgument("startTime", from: arguments, fieldName: fieldName),
        endTime: try extractOptionalStringArgument("endTime", from: arguments, fieldName: fieldName),
        sinceId: try extractOptionalStringArgument("sinceId", from: arguments, fieldName: fieldName),
        untilId: try extractOptionalStringArgument("untilId", from: arguments, fieldName: fieldName),
        nextToken: try extractOptionalStringArgument("nextToken", from: arguments, fieldName: fieldName),
        paginationToken: try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: fieldName),
        sortOrder: sortOrder,
        maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 10, maximum: 500, fieldName: fieldName)
    )
}

private func extractPostCountsRequestOptions(
    from arguments: String,
    fieldName: String
) throws -> PostCountsRequestOptions {
    let granularity = try extractOptionalStringArgument("granularity", from: arguments, fieldName: fieldName) ?? "day"
    guard ["minute", "hour", "day"].contains(granularity) else {
        throw validation("\(fieldName).granularity must be one of: minute, hour, day.")
    }
    return PostCountsRequestOptions(
        startTime: try extractOptionalStringArgument("startTime", from: arguments, fieldName: fieldName),
        endTime: try extractOptionalStringArgument("endTime", from: arguments, fieldName: fieldName),
        sinceId: try extractOptionalStringArgument("sinceId", from: arguments, fieldName: fieldName),
        untilId: try extractOptionalStringArgument("untilId", from: arguments, fieldName: fieldName),
        nextToken: try extractOptionalStringArgument("nextToken", from: arguments, fieldName: fieldName),
        paginationToken: try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: fieldName),
        granularity: granularity
    )
}
