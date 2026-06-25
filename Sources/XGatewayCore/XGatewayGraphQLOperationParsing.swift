import Foundation

enum SupportedGraphQLOperation {
    case accountMe
    case apiUsage(days: Int)
    case post(postId: String, readOptions: XGatewayPostReadOptions, replyExpansion: ReplyExpansionRequest?)
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

    var fieldName: String {
        switch self {
        case .accountMe:
            return "accountMe"
        case .apiUsage:
            return "apiUsage"
        case .post:
            return "post"
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
        }
    }

    var supportsOAuth1: Bool {
        switch self {
        case .apiUsage:
            return false
        default:
            return true
        }
    }

    var requiresOAuth1: Bool {
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
    "searchPosts",
    "homeTimeline",
    "followingTimeline",
    "userTimeline",
    "mentionsTimeline",
    "post"
]

let supportedMutationGraphQLFields = [
    "createPost",
    "deletePost",
    "replyToPost",
    "quotePost",
    "unrepostPost",
    "repostPost"
]

private let supportedGraphQLFieldDescription = (supportedQueryGraphQLFields + supportedMutationGraphQLFields)
    .joined(separator: ", ")

private enum SupportedGraphQLFieldArguments {
    static let accountMe = GraphQLArgumentSet.noArguments
    static let apiUsage: Set<String> = ["days"]
    static let post = GraphQLArgumentSet.postReadOptions.union(["id"])
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
    case .mutation:
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
