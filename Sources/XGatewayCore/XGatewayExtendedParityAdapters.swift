import Foundation

extension XGatewayLiveExecutor {
    func executeExtendedParityOperation(
        operation: SupportedGraphQLOperation,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any]? {
        if let result = try executeExtendedReadOperation(operation: operation, authorization: authorization) {
            return result
        }
        if let result = try executeExtendedSocialMutation(operation: operation, authorization: authorization) {
            return result
        }
        if let result = try executeExtendedListMutation(operation: operation, authorization: authorization) {
            return result
        }
        return try executeExtendedDMMutation(operation: operation, authorization: authorization)
    }

    private func executeExtendedReadOperation(
        operation: SupportedGraphQLOperation,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any]? {
        switch operation {
        case .users(let ids):
            return [operation.fieldName: try users(ids: ids, authorization: authorization)]
        case .usersByUsernames(let usernames):
            return [operation.fieldName: try usersByUsernames(usernames: usernames, authorization: authorization)]
        case .posts(let ids, let readOptions, let replyExpansion):
            let page = try posts(ids: ids, readOptions: readOptions.withDefaultMediaRootDir(mediaRootDir), authorization: authorization)
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .likedPosts(let userId, let maxResults, let paginationToken, let readOptions, let replyExpansion):
            let page = try likedPosts(
                userId: userId,
                maxResults: maxResults,
                paginationToken: paginationToken,
                readOptions: readOptions.withDefaultMediaRootDir(mediaRootDir),
                authorization: authorization
            )
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .mutedUsers(let userId, let maxResults, let paginationToken):
            return [operation.fieldName: try userConnection(path: "/2/users/\(urlPathEscape(userId))/muting", maxResults: maxResults, paginationToken: paginationToken, authorization: authorization)]
        case .blockedUsers(let userId, let maxResults, let paginationToken):
            return [operation.fieldName: try userConnection(path: "/2/users/\(urlPathEscape(userId))/blocking", maxResults: maxResults, paginationToken: paginationToken, authorization: authorization)]
        case .list(let listId):
            return [operation.fieldName: try list(listId: listId, authorization: authorization)]
        case .ownedLists(let userId, let maxResults, let paginationToken):
            return [operation.fieldName: try listPage(path: "/2/users/\(urlPathEscape(userId))/owned_lists", maxResults: maxResults, paginationToken: paginationToken, authorization: authorization)]
        case .followedLists(let userId, let maxResults, let paginationToken):
            return [operation.fieldName: try listPage(path: "/2/users/\(urlPathEscape(userId))/followed_lists", maxResults: maxResults, paginationToken: paginationToken, authorization: authorization)]
        case .listMemberships(let userId, let maxResults, let paginationToken):
            return [operation.fieldName: try listPage(path: "/2/users/\(urlPathEscape(userId))/list_memberships", maxResults: maxResults, paginationToken: paginationToken, authorization: authorization)]
        case .pinnedLists(let userId):
            return [operation.fieldName: try listPage(path: "/2/users/\(urlPathEscape(userId))/pinned_lists", authorization: authorization)]
        case .listFollowers(let listId, let maxResults, let paginationToken):
            return [operation.fieldName: try userConnection(path: "/2/lists/\(urlPathEscape(listId))/followers", maxResults: maxResults, paginationToken: paginationToken, authorization: authorization)]
        case .listMembers(let listId, let maxResults, let paginationToken):
            return [operation.fieldName: try userConnection(path: "/2/lists/\(urlPathEscape(listId))/members", maxResults: maxResults, paginationToken: paginationToken, authorization: authorization)]
        case .listPosts(let listId, let maxResults, let paginationToken, let readOptions, let replyExpansion):
            let page = try listPosts(
                listId: listId,
                maxResults: maxResults,
                paginationToken: paginationToken,
                readOptions: readOptions.withDefaultMediaRootDir(mediaRootDir),
                authorization: authorization
            )
            return [operation.fieldName: try hydrateReplies(inPage: page, expansion: replyExpansion, authorization: authorization)]
        case .dmEvents(let maxResults, let paginationToken, let eventTypes):
            return [operation.fieldName: try dmEvents(path: "/2/dm_events", maxResults: maxResults, paginationToken: paginationToken, eventTypes: eventTypes, authorization: authorization)]
        case .dmEvent(let eventId):
            return [operation.fieldName: try dmEvent(eventId: eventId, authorization: authorization)]
        case .dmConversationEvents(let participantId, let maxResults, let paginationToken, let eventTypes):
            let path = "/2/dm_conversations/with/\(urlPathEscape(participantId))/dm_events"
            return [
                operation.fieldName: try dmEvents(
                    path: path,
                    maxResults: maxResults,
                    paginationToken: paginationToken,
                    eventTypes: eventTypes,
                    authorization: authorization
                )
            ]
        case .dmConversationEventsById(let conversationId, let maxResults, let paginationToken, let eventTypes):
            let path = "/2/dm_conversations/\(urlPathEscape(conversationId))/dm_events"
            return [
                operation.fieldName: try dmEvents(
                    path: path,
                    maxResults: maxResults,
                    paginationToken: paginationToken,
                    eventTypes: eventTypes,
                    authorization: authorization
                )
            ]
        default:
            return nil
        }
    }

    private func executeExtendedSocialMutation(
        operation: SupportedGraphQLOperation,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any]? {
        switch operation {
        case .likePost(let postId):
            return [operation.fieldName: try postAction(postId: postId, actionKey: "liked", pathSuffix: "likes", bodyKey: "tweet_id", authorization: authorization)]
        case .unlikePost(let postId):
            let userId = try authenticatedUserId(authorization: authorization)
            let payload = try performJSONRequest(
                method: "DELETE",
                url: try xAPIURL(path: "/2/users/\(urlPathEscape(userId))/likes/\(urlPathEscape(postId))"),
                authorization: authorization,
                body: nil
            )
            return [operation.fieldName: XGatewayExtendedProjector.booleanResult(id: postId, key: "liked", payload, defaultValue: false)]
        case .followUser(let targetUserId):
            return [operation.fieldName: try userAction(targetUserId: targetUserId, actionKey: "following", pathSuffix: "following", bodyKey: "target_user_id", authorization: authorization)]
        case .unfollowUser(let targetUserId):
            let userId = try authenticatedUserId(authorization: authorization)
            let payload = try performJSONRequest(
                method: "DELETE",
                url: try xAPIURL(path: "/2/users/\(urlPathEscape(userId))/following/\(urlPathEscape(targetUserId))"),
                authorization: authorization,
                body: nil
            )
            return [operation.fieldName: XGatewayExtendedProjector.booleanResult(id: targetUserId, key: "following", payload, defaultValue: false)]
        case .muteUser(let targetUserId):
            return [operation.fieldName: try userAction(targetUserId: targetUserId, actionKey: "muting", pathSuffix: "muting", bodyKey: "target_user_id", authorization: authorization)]
        case .unmuteUser(let targetUserId):
            let userId = try authenticatedUserId(authorization: authorization)
            let payload = try performJSONRequest(
                method: "DELETE",
                url: try xAPIURL(path: "/2/users/\(urlPathEscape(userId))/muting/\(urlPathEscape(targetUserId))"),
                authorization: authorization,
                body: nil
            )
            return [operation.fieldName: XGatewayExtendedProjector.booleanResult(id: targetUserId, key: "muting", payload, defaultValue: false)]
        default:
            return nil
        }
    }

    private func executeExtendedListMutation(
        operation: SupportedGraphQLOperation,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any]? {
        switch operation {
        case .createList(let name, let description, let isPrivate):
            return [operation.fieldName: try createList(name: name, description: description, isPrivate: isPrivate, authorization: authorization)]
        case .updateList(let listId, let name, let description, let isPrivate):
            return [operation.fieldName: try updateList(listId: listId, name: name, description: description, isPrivate: isPrivate, authorization: authorization)]
        case .deleteList(let listId):
            let payload = try performJSONRequest(method: "DELETE", url: try xAPIURL(path: "/2/lists/\(urlPathEscape(listId))"), authorization: authorization, body: nil)
            return [operation.fieldName: XGatewayExtendedProjector.booleanResult(id: listId, key: "deleted", payload, defaultValue: true)]
        case .addListMember(let listId, let userId):
            return [operation.fieldName: try listMemberAction(listId: listId, userId: userId, defaultValue: true, authorization: authorization)]
        case .removeListMember(let listId, let userId):
            let payload = try performJSONRequest(method: "DELETE", url: try xAPIURL(path: "/2/lists/\(urlPathEscape(listId))/members/\(urlPathEscape(userId))"), authorization: authorization, body: nil)
            return [operation.fieldName: XGatewayExtendedProjector.booleanResult(id: userId, key: "isMember", payload, upstreamKey: "is_member", defaultValue: false)]
        case .followList(let listId):
            return [operation.fieldName: try listRelationshipAction(listId: listId, pathSuffix: "followed_lists", key: "following", authorization: authorization)]
        case .unfollowList(let listId):
            return [operation.fieldName: try deleteListRelationship(listId: listId, pathSuffix: "followed_lists", key: "following", authorization: authorization)]
        case .pinList(let listId):
            return [operation.fieldName: try listRelationshipAction(listId: listId, pathSuffix: "pinned_lists", key: "pinned", authorization: authorization)]
        case .unpinList(let listId):
            return [operation.fieldName: try deleteListRelationship(listId: listId, pathSuffix: "pinned_lists", key: "pinned", authorization: authorization)]
        default:
            return nil
        }
    }

    private func executeExtendedDMMutation(
        operation: SupportedGraphQLOperation,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any]? {
        switch operation {
        case .createDirectMessage(let participantId, let text, let attachments):
            return [
                operation.fieldName: try createDirectMessage(
                    path: "/2/dm_conversations/with/\(urlPathEscape(participantId))/messages",
                    text: text,
                    attachments: attachments,
                    authorization: authorization
                )
            ]
        case .createDirectMessageInConversation(let conversationId, let text, let attachments):
            return [
                operation.fieldName: try createDirectMessage(
                    path: "/2/dm_conversations/\(urlPathEscape(conversationId))/messages",
                    text: text,
                    attachments: attachments,
                    authorization: authorization
                )
            ]
        case .createDirectMessageConversation(let participantIds, let text, let attachments):
            return [
                operation.fieldName: try createDirectMessageConversation(
                    participantIds: participantIds,
                    text: text,
                    attachments: attachments,
                    authorization: authorization
                )
            ]
        case .deleteDirectMessage(let eventId):
            let payload = try performJSONRequest(method: "DELETE", url: try xAPIURL(path: "/2/dm_events/\(urlPathEscape(eventId))"), authorization: authorization, body: nil)
            return [operation.fieldName: XGatewayExtendedProjector.booleanResult(id: eventId, key: "deleted", payload, defaultValue: true)]
        default:
            return nil
        }
    }

    func users(ids: [String], authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: "/2/users", query: userPageQueryItems(["ids": ids.joined(separator: ",")])),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.userPage(payload)
    }

    func usersByUsernames(usernames: [String], authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: "/2/users/by", query: userPageQueryItems(["usernames": usernames.joined(separator: ",")])),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.userPage(payload)
    }

    func posts(ids: [String], readOptions: XGatewayPostReadOptions, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: "/2/tweets", query: timelineQueryItems(["ids": ids.joined(separator: ",")])),
            authorization: authorization,
            body: nil
        )
        return try XGatewayResponseProjector.postPage(payload, options: readOptions)
    }

    func likedPosts(
        userId: String,
        maxResults: Int,
        paginationToken: String?,
        readOptions: XGatewayPostReadOptions,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(
                path: "/2/users/\(urlPathEscape(userId))/liked_tweets",
                query: extendedPostPageQuery(maxResults: maxResults, paginationToken: paginationToken)
            ),
            authorization: authorization,
            body: nil
        )
        return try XGatewayResponseProjector.postPage(payload, options: readOptions)
    }

    func userConnection(
        path: String,
        maxResults: Int,
        paginationToken: String?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: path, query: extendedUserPageQuery(maxResults: maxResults, paginationToken: paginationToken)),
            authorization: authorization,
            body: nil
        )
        return XGatewayResponseProjector.userPage(payload)
    }

    func list(listId: String, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: "/2/lists/\(urlPathEscape(listId))", query: extendedListQueryItems([:])),
            authorization: authorization,
            body: nil
        )
        return XGatewayExtendedProjector.list(payload)
    }

    func listPage(path: String, maxResults: Int, paginationToken: String?, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: path, query: extendedListPageQuery(maxResults: maxResults, paginationToken: paginationToken)),
            authorization: authorization,
            body: nil
        )
        return XGatewayExtendedProjector.listPage(payload)
    }

    func listPage(path: String, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: path, query: extendedListQueryItems([:])),
            authorization: authorization,
            body: nil
        )
        return XGatewayExtendedProjector.listPage(payload)
    }

    func listPosts(
        listId: String,
        maxResults: Int,
        paginationToken: String?,
        readOptions: XGatewayPostReadOptions,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(
                path: "/2/lists/\(urlPathEscape(listId))/tweets",
                query: extendedPostPageQuery(maxResults: maxResults, paginationToken: paginationToken)
            ),
            authorization: authorization,
            body: nil
        )
        return try XGatewayResponseProjector.postPage(payload, options: readOptions)
    }

    func dmEvents(
        path: String,
        maxResults: Int,
        paginationToken: String?,
        eventTypes: [String]?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: path, query: dmEventPageQuery(maxResults: maxResults, paginationToken: paginationToken, eventTypes: eventTypes)),
            authorization: authorization,
            body: nil
        )
        return XGatewayExtendedProjector.dmEventPage(payload)
    }

    func dmEvent(eventId: String, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "GET",
            url: try xAPIURL(path: "/2/dm_events/\(urlPathEscape(eventId))", query: dmEventQueryItems([:])),
            authorization: authorization,
            body: nil
        )
        return XGatewayExtendedProjector.dmEvent(payload)
    }

    func postAction(
        postId: String,
        actionKey: String,
        pathSuffix: String,
        bodyKey: String,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let userId = try authenticatedUserId(authorization: authorization)
        let payload = try performJSONRequest(
            method: "POST",
            url: try xAPIURL(path: "/2/users/\(urlPathEscape(userId))/\(pathSuffix)"),
            authorization: authorization,
            body: [bodyKey: postId]
        )
        return XGatewayExtendedProjector.booleanResult(id: postId, key: actionKey, payload, defaultValue: true)
    }

    func userAction(
        targetUserId: String,
        actionKey: String,
        pathSuffix: String,
        bodyKey: String,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let userId = try authenticatedUserId(authorization: authorization)
        let payload = try performJSONRequest(
            method: "POST",
            url: try xAPIURL(path: "/2/users/\(urlPathEscape(userId))/\(pathSuffix)"),
            authorization: authorization,
            body: [bodyKey: targetUserId]
        )
        return XGatewayExtendedProjector.booleanResult(id: targetUserId, key: actionKey, payload, defaultValue: true)
    }

    func createList(name: String, description: String?, isPrivate: Bool, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        var body: [String: Any] = ["name": name, "private": isPrivate]
        extendedCopyIfPresent(description, to: "description", into: &body)
        let payload = try performJSONRequest(method: "POST", url: try xAPIURL(path: "/2/lists"), authorization: authorization, body: body)
        return XGatewayExtendedProjector.list(payload)
    }

    func updateList(
        listId: String,
        name: String?,
        description: String?,
        isPrivate: Bool?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        var body: [String: Any] = [:]
        extendedCopyIfPresent(name, to: "name", into: &body)
        extendedCopyIfPresent(description, to: "description", into: &body)
        if let isPrivate {
            body["private"] = isPrivate
        }
        let payload = try performJSONRequest(method: "PUT", url: try xAPIURL(path: "/2/lists/\(urlPathEscape(listId))"), authorization: authorization, body: body)
        return XGatewayExtendedProjector.booleanResult(id: listId, key: "updated", payload, defaultValue: true)
    }

    func listMemberAction(listId: String, userId: String, defaultValue: Bool, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "POST",
            url: try xAPIURL(path: "/2/lists/\(urlPathEscape(listId))/members"),
            authorization: authorization,
            body: ["user_id": userId]
        )
        return XGatewayExtendedProjector.booleanResult(id: userId, key: "isMember", payload, upstreamKey: "is_member", defaultValue: defaultValue)
    }

    func listRelationshipAction(listId: String, pathSuffix: String, key: String, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let userId = try authenticatedUserId(authorization: authorization)
        let payload = try performJSONRequest(
            method: "POST",
            url: try xAPIURL(path: "/2/users/\(urlPathEscape(userId))/\(pathSuffix)"),
            authorization: authorization,
            body: ["list_id": listId]
        )
        return XGatewayExtendedProjector.booleanResult(id: listId, key: key, payload, defaultValue: true)
    }

    func deleteListRelationship(listId: String, pathSuffix: String, key: String, authorization: XGatewayRequestAuthorization) throws -> [String: Any] {
        let userId = try authenticatedUserId(authorization: authorization)
        let payload = try performJSONRequest(
            method: "DELETE",
            url: try xAPIURL(path: "/2/users/\(urlPathEscape(userId))/\(pathSuffix)/\(urlPathEscape(listId))"),
            authorization: authorization,
            body: nil
        )
        return XGatewayExtendedProjector.booleanResult(id: listId, key: key, payload, defaultValue: false)
    }

    func createDirectMessage(
        path: String,
        text: String,
        attachments: [PostAttachmentInput]?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "POST",
            url: try xAPIURL(path: path),
            authorization: authorization,
            body: try directMessageBody(text: text, attachments: attachments, authorization: authorization)
        )
        return XGatewayExtendedProjector.dmEvent(payload)
    }

    func createDirectMessageConversation(
        participantIds: [String],
        text: String,
        attachments: [PostAttachmentInput]?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let payload = try performJSONRequest(
            method: "POST",
            url: try xAPIURL(path: "/2/dm_conversations"),
            authorization: authorization,
            body: [
                "conversation_type": "Group",
                "participant_ids": participantIds,
                "message": try directMessageBody(text: text, attachments: attachments, authorization: authorization)
            ]
        )
        return XGatewayExtendedProjector.dmEvent(payload)
    }
}

private func extendedUserPageQuery(maxResults: Int, paginationToken: String?) -> String {
    var items = ["max_results": String(maxResults)]
    extendedCopyIfPresent(paginationToken, to: "pagination_token", into: &items)
    return userPageQueryItems(items)
}

private func extendedPostPageQuery(maxResults: Int, paginationToken: String?) -> String {
    var items = ["max_results": String(maxResults)]
    extendedCopyIfPresent(paginationToken, to: "pagination_token", into: &items)
    return timelineQueryItems(items)
}

private func extendedListPageQuery(maxResults: Int, paginationToken: String?) -> String {
    var items = ["max_results": String(maxResults)]
    extendedCopyIfPresent(paginationToken, to: "pagination_token", into: &items)
    return extendedListQueryItems(items)
}

private func extendedListQueryItems(_ additionalItems: [String: String]) -> String {
    var items = additionalItems
    items["list.fields"] = "created_at,description,follower_count,id,member_count,name,owner_id,private"
    items["user.fields"] = "id,name,username"
    return queryItems(items)
}

private func dmEventPageQuery(maxResults: Int, paginationToken: String?, eventTypes: [String]?) -> String {
    var items = ["max_results": String(maxResults)]
    extendedCopyIfPresent(paginationToken, to: "pagination_token", into: &items)
    if let eventTypes,
       !eventTypes.isEmpty {
        items["event_types"] = eventTypes.joined(separator: ",")
    }
    return dmEventQueryItems(items)
}

private func dmEventQueryItems(_ additionalItems: [String: String]) -> String {
    var items = additionalItems
    items["dm_event.fields"] = "attachments,created_at,dm_conversation_id,event_type,id,participant_ids,referenced_tweets,sender_id,text"
    items["expansions"] = "attachments.media_keys,participant_ids,referenced_tweets.id,sender_id"
    items["media.fields"] = "duration_ms,height,media_key,preview_image_url,type,url,width"
    items["tweet.fields"] = "author_id,created_at,id,text"
    items["user.fields"] = "id,name,username"
    return queryItems(items)
}

private func extendedCopyIfPresent(_ value: String?, to key: String, into items: inout [String: String]) {
    guard let value = nonBlank(value) else {
        return
    }
    items[key] = value
}

private func extendedCopyIfPresent(_ value: String?, to key: String, into items: inout [String: Any]) {
    guard let value = nonBlank(value) else {
        return
    }
    items[key] = value
}
