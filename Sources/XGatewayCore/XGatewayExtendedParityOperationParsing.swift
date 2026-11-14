import Foundation

private enum ExtendedGraphQLArguments {
    static let ids: Set<String> = ["ids"]
    static let usernames: Set<String> = ["usernames"]
    static let userPage: Set<String> = ["userId", "maxResults", "paginationToken"]
    static let pinnedLists: Set<String> = ["userId"]
    static let listPage: Set<String> = ["listId", "maxResults", "paginationToken"]
    static let listPosts = GraphQLArgumentSet.pagedPostReadOptions.union(["listId"])
    static let posts = GraphQLArgumentSet.postReadOptions.union(["ids"])
    static let likedPosts = GraphQLArgumentSet.pagedPostReadOptions.union(["userId"])
    static let list: Set<String> = ["id"]
    static let dmEvents: Set<String> = ["maxResults", "paginationToken", "eventTypes"]
    static let dmEvent: Set<String> = ["id"]
    static let dmConversationEvents: Set<String> = ["participantId", "maxResults", "paginationToken", "eventTypes"]
    static let dmConversationEventsById: Set<String> = ["conversationId", "maxResults", "paginationToken", "eventTypes"]
    static let postAction: Set<String> = ["postId"]
    static let userAction: Set<String> = ["targetUserId"]
    static let createList: Set<String> = ["name", "description", "private"]
    static let updateList: Set<String> = ["listId", "name", "description", "private"]
    static let deleteList: Set<String> = ["listId"]
    static let listMember: Set<String> = ["listId", "userId"]
    static let listAction: Set<String> = ["listId"]
    static let createDirectMessage: Set<String> = ["participantId", "text", "attachments"]
    static let createDirectMessageInConversation: Set<String> = ["conversationId", "text", "attachments"]
    static let createDirectMessageConversation: Set<String> = ["participantIds", "text", "attachments"]
    static let deleteDirectMessage: Set<String> = ["eventId"]
}

func parseExtendedParityQueryOperation(
    fieldName: String?,
    arguments: String,
    document: String,
    operationType: XGatewayGraphQLOperationType
) throws -> SupportedGraphQLOperation? {
    if fieldName == "users" {
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.ids, fieldName: "users")
        return .users(ids: try extractStringArrayArgument("ids", from: arguments, fieldName: "users", maximum: 100))
    }
    if fieldName == "usersByUsernames" {
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.usernames, fieldName: "usersByUsernames")
        return .usersByUsernames(
            usernames: try extractStringArrayArgument("usernames", from: arguments, fieldName: "usersByUsernames", maximum: 100)
        )
    }
    if fieldName == "posts" {
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.posts, fieldName: "posts")
        return .posts(
            ids: try extractStringArrayArgument("ids", from: arguments, fieldName: "posts", maximum: 100),
            readOptions: try extractPostReadOptions(from: arguments, fieldName: "posts"),
            replyExpansion: try extractReplyExpansion(from: document, operationType: operationType, selectionPath: "posts.posts")
        )
    }
    if fieldName == "likedPosts" {
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.likedPosts, fieldName: "likedPosts")
        return .likedPosts(
            userId: try extractStringArgument("userId", from: arguments, fieldName: "likedPosts"),
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 5, maximum: 100, fieldName: "likedPosts"),
            paginationToken: try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: "likedPosts"),
            readOptions: try extractPostReadOptions(from: arguments, fieldName: "likedPosts"),
            replyExpansion: try extractReplyExpansion(from: document, operationType: operationType, selectionPath: "likedPosts.posts")
        )
    }
    if fieldName == "mutedUsers" {
        return try parseUserPageOperation(arguments: arguments, fieldName: "mutedUsers", factory: SupportedGraphQLOperation.mutedUsers)
    }
    if fieldName == "blockedUsers" {
        return try parseUserPageOperation(arguments: arguments, fieldName: "blockedUsers", factory: SupportedGraphQLOperation.blockedUsers)
    }
    if fieldName == "list" {
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.list, fieldName: "list")
        return .list(listId: try extractStringArgument("id", from: arguments, fieldName: "list"))
    }
    if fieldName == "ownedLists" {
        return try parseUserListPageOperation(arguments: arguments, fieldName: "ownedLists", factory: SupportedGraphQLOperation.ownedLists)
    }
    if fieldName == "followedLists" {
        return try parseUserListPageOperation(arguments: arguments, fieldName: "followedLists", factory: SupportedGraphQLOperation.followedLists)
    }
    if fieldName == "listMemberships" {
        return try parseUserListPageOperation(arguments: arguments, fieldName: "listMemberships", factory: SupportedGraphQLOperation.listMemberships)
    }
    if fieldName == "pinnedLists" {
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.pinnedLists, fieldName: "pinnedLists")
        return .pinnedLists(userId: try extractStringArgument("userId", from: arguments, fieldName: "pinnedLists"))
    }
    if fieldName == "listFollowers" {
        return try parseListUserPageOperation(arguments: arguments, fieldName: "listFollowers", factory: SupportedGraphQLOperation.listFollowers)
    }
    if fieldName == "listMembers" {
        return try parseListUserPageOperation(arguments: arguments, fieldName: "listMembers", factory: SupportedGraphQLOperation.listMembers)
    }
    if fieldName == "listPosts" {
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.listPosts, fieldName: "listPosts")
        return .listPosts(
            listId: try extractStringArgument("listId", from: arguments, fieldName: "listPosts"),
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 10, minimum: 1, maximum: 100, fieldName: "listPosts"),
            paginationToken: try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: "listPosts"),
            readOptions: try extractPostReadOptions(from: arguments, fieldName: "listPosts"),
            replyExpansion: try extractReplyExpansion(from: document, operationType: operationType, selectionPath: "listPosts.posts")
        )
    }
    if fieldName == "dmEvents" {
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.dmEvents, fieldName: "dmEvents")
        return .dmEvents(
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 100, minimum: 1, maximum: 100, fieldName: "dmEvents"),
            paginationToken: try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: "dmEvents"),
            eventTypes: try extractDmEventTypes(arguments, fieldName: "dmEvents")
        )
    }
    if fieldName == "dmEvent" {
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.dmEvent, fieldName: "dmEvent")
        return .dmEvent(eventId: try extractStringArgument("id", from: arguments, fieldName: "dmEvent"))
    }
    if fieldName == "dmConversationEvents" {
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.dmConversationEvents, fieldName: "dmConversationEvents")
        return .dmConversationEvents(
            participantId: try extractStringArgument("participantId", from: arguments, fieldName: "dmConversationEvents"),
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 100, minimum: 1, maximum: 100, fieldName: "dmConversationEvents"),
            paginationToken: try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: "dmConversationEvents"),
            eventTypes: try extractDmEventTypes(arguments, fieldName: "dmConversationEvents")
        )
    }
    if fieldName == "dmConversationEventsById" {
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.dmConversationEventsById, fieldName: "dmConversationEventsById")
        return .dmConversationEventsById(
            conversationId: try extractStringArgument("conversationId", from: arguments, fieldName: "dmConversationEventsById"),
            maxResults: try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 100, minimum: 1, maximum: 100, fieldName: "dmConversationEventsById"),
            paginationToken: try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: "dmConversationEventsById"),
            eventTypes: try extractDmEventTypes(arguments, fieldName: "dmConversationEventsById")
        )
    }
    return nil
}

func parseExtendedParityMutationOperation(fieldName: String?, arguments: String) throws -> SupportedGraphQLOperation? {
    switch fieldName {
    case "likePost":
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.postAction, fieldName: "likePost")
        return .likePost(postId: try extractStringArgument("postId", from: arguments, fieldName: "likePost"))
    case "unlikePost":
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.postAction, fieldName: "unlikePost")
        return .unlikePost(postId: try extractStringArgument("postId", from: arguments, fieldName: "unlikePost"))
    case "followUser":
        return try parseUserAction(arguments: arguments, fieldName: "followUser", factory: SupportedGraphQLOperation.followUser)
    case "unfollowUser":
        return try parseUserAction(arguments: arguments, fieldName: "unfollowUser", factory: SupportedGraphQLOperation.unfollowUser)
    case "muteUser":
        return try parseUserAction(arguments: arguments, fieldName: "muteUser", factory: SupportedGraphQLOperation.muteUser)
    case "unmuteUser":
        return try parseUserAction(arguments: arguments, fieldName: "unmuteUser", factory: SupportedGraphQLOperation.unmuteUser)
    case "createList":
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.createList, fieldName: "createList")
        return .createList(
            name: try extractStringArgument("name", from: arguments, fieldName: "createList"),
            description: try extractOptionalStringArgument("description", from: arguments, fieldName: "createList"),
            isPrivate: try extractOptionalBoolArgument("private", from: arguments, defaultValue: false, fieldName: "createList")
        )
    case "updateList":
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.updateList, fieldName: "updateList")
        return .updateList(
            listId: try extractStringArgument("listId", from: arguments, fieldName: "updateList"),
            name: try extractOptionalStringArgument("name", from: arguments, fieldName: "updateList"),
            description: try extractOptionalStringArgument("description", from: arguments, fieldName: "updateList"),
            isPrivate: try extractOptionalBoolIfPresent("private", from: arguments, fieldName: "updateList")
        )
    case "deleteList":
        return try parseListAction(arguments: arguments, fieldName: "deleteList", factory: SupportedGraphQLOperation.deleteList)
    case "addListMember":
        return try parseListMemberAction(arguments: arguments, fieldName: "addListMember", factory: SupportedGraphQLOperation.addListMember)
    case "removeListMember":
        return try parseListMemberAction(arguments: arguments, fieldName: "removeListMember", factory: SupportedGraphQLOperation.removeListMember)
    case "followList":
        return try parseListAction(arguments: arguments, fieldName: "followList", factory: SupportedGraphQLOperation.followList)
    case "unfollowList":
        return try parseListAction(arguments: arguments, fieldName: "unfollowList", factory: SupportedGraphQLOperation.unfollowList)
    case "pinList":
        return try parseListAction(arguments: arguments, fieldName: "pinList", factory: SupportedGraphQLOperation.pinList)
    case "unpinList":
        return try parseListAction(arguments: arguments, fieldName: "unpinList", factory: SupportedGraphQLOperation.unpinList)
    case "createDirectMessage":
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.createDirectMessage, fieldName: "createDirectMessage")
        return .createDirectMessage(
            participantId: try extractStringArgument("participantId", from: arguments, fieldName: "createDirectMessage"),
            text: try extractStringArgument("text", from: arguments, fieldName: "createDirectMessage"),
            attachments: try extractPostAttachmentsIfPresent(from: arguments, fieldName: "createDirectMessage")
        )
    case "createDirectMessageInConversation":
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.createDirectMessageInConversation, fieldName: "createDirectMessageInConversation")
        return .createDirectMessageInConversation(
            conversationId: try extractStringArgument("conversationId", from: arguments, fieldName: "createDirectMessageInConversation"),
            text: try extractStringArgument("text", from: arguments, fieldName: "createDirectMessageInConversation"),
            attachments: try extractPostAttachmentsIfPresent(from: arguments, fieldName: "createDirectMessageInConversation")
        )
    case "createDirectMessageConversation":
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.createDirectMessageConversation, fieldName: "createDirectMessageConversation")
        return .createDirectMessageConversation(
            participantIds: try extractStringArrayArgument("participantIds", from: arguments, fieldName: "createDirectMessageConversation", minimum: 2, maximum: 50),
            text: try extractStringArgument("text", from: arguments, fieldName: "createDirectMessageConversation"),
            attachments: try extractPostAttachmentsIfPresent(from: arguments, fieldName: "createDirectMessageConversation")
        )
    case "deleteDirectMessage":
        try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.deleteDirectMessage, fieldName: "deleteDirectMessage")
        return .deleteDirectMessage(eventId: try extractStringArgument("eventId", from: arguments, fieldName: "deleteDirectMessage"))
    default:
        return nil
    }
}

private func parseUserPageOperation(
    arguments: String,
    fieldName: String,
    factory: (String, Int, String?) -> SupportedGraphQLOperation
) throws -> SupportedGraphQLOperation {
    try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.userPage, fieldName: fieldName)
    return factory(
        try extractStringArgument("userId", from: arguments, fieldName: fieldName),
        try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 100, minimum: 1, maximum: 1_000, fieldName: fieldName),
        try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: fieldName)
    )
}

private func parseUserListPageOperation(
    arguments: String,
    fieldName: String,
    factory: (String, Int, String?) -> SupportedGraphQLOperation
) throws -> SupportedGraphQLOperation {
    return try parseUserPageOperation(arguments: arguments, fieldName: fieldName, factory: factory)
}

private func parseListUserPageOperation(
    arguments: String,
    fieldName: String,
    factory: (String, Int, String?) -> SupportedGraphQLOperation
) throws -> SupportedGraphQLOperation {
    try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.listPage, fieldName: fieldName)
    return factory(
        try extractStringArgument("listId", from: arguments, fieldName: fieldName),
        try extractOptionalIntArgument("maxResults", from: arguments, defaultValue: 100, minimum: 1, maximum: 1_000, fieldName: fieldName),
        try extractOptionalStringArgument("paginationToken", from: arguments, fieldName: fieldName)
    )
}

private func parseUserAction(
    arguments: String,
    fieldName: String,
    factory: (String) -> SupportedGraphQLOperation
) throws -> SupportedGraphQLOperation {
    try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.userAction, fieldName: fieldName)
    return factory(try extractStringArgument("targetUserId", from: arguments, fieldName: fieldName))
}

private func parseListAction(
    arguments: String,
    fieldName: String,
    factory: (String) -> SupportedGraphQLOperation
) throws -> SupportedGraphQLOperation {
    try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.listAction, fieldName: fieldName)
    return factory(try extractStringArgument("listId", from: arguments, fieldName: fieldName))
}

private func parseListMemberAction(
    arguments: String,
    fieldName: String,
    factory: (String, String) -> SupportedGraphQLOperation
) throws -> SupportedGraphQLOperation {
    try validateGraphQLArguments(in: arguments, allowed: ExtendedGraphQLArguments.listMember, fieldName: fieldName)
    return factory(
        try extractStringArgument("listId", from: arguments, fieldName: fieldName),
        try extractStringArgument("userId", from: arguments, fieldName: fieldName)
    )
}

private func extractOptionalBoolIfPresent(_ name: String, from arguments: String, fieldName: String) throws -> Bool? {
    guard rangeOfGraphQLArgument(name, in: arguments) != nil else {
        return nil
    }
    return try extractOptionalBoolArgument(name, from: arguments, defaultValue: false, fieldName: fieldName)
}

private func extractDmEventTypes(_ arguments: String, fieldName: String) throws -> [String]? {
    let values = try extractOptionalStringArrayArgument("eventTypes", from: arguments, fieldName: fieldName, maximum: 3)
    let allowed = Set(["MessageCreate", "ParticipantsJoin", "ParticipantsLeave"])
    for value in values ?? [] where !allowed.contains(value) {
        throw validation("\(fieldName).eventTypes must contain only: MessageCreate, ParticipantsJoin, ParticipantsLeave.")
    }
    return values
}
