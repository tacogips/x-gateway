import Foundation

let openAPIParityQueryFields = openAPIParityQueryDefinitions.map(\.fieldName)
let openAPIParityMutationFields = openAPIParityMutationDefinitions.map(\.fieldName)

struct OpenAPIParityRequest {
    let fieldName: String
    let method: String
    let path: String
    let query: [String: String]
    let body: [String: Any]?
}

private struct OpenAPIParityDefinition {
    let fieldName: String
    let method: String
    let pathTemplate: String
    let pathParameters: [String]
    let queryParameters: [OpenAPIParityParameter]
    let bodyParameters: [OpenAPIParityParameter]
    let bodyBuilder: ((String, String) throws -> [String: Any]?)?
}

private struct OpenAPIParityParameter {
    let graphQLName: String
    let upstreamName: String
    let kind: OpenAPIParityValueKind
}

private enum OpenAPIParityValueKind {
    case string(required: Bool)
    case stringArray(required: Bool, maximum: Int)
    case int(required: Bool, defaultValue: Int?, minimum: Int, maximum: Int)
    case bool(required: Bool, defaultValue: Bool?)
}

private let commonPageParameters = [
    stringParam("paginationToken", upstream: "pagination_token"),
    intParam("maxResults", upstream: "max_results", defaultValue: nil, minimum: 1, maximum: 1_000)
]

private let countQueryParameters = [
    stringParam("query", required: true),
    stringParam("startTime", upstream: "start_time"),
    stringParam("endTime", upstream: "end_time"),
    stringParam("sinceId", upstream: "since_id"),
    stringParam("untilId", upstream: "until_id"),
    stringParam("nextToken", upstream: "next_token"),
    stringParam("paginationToken", upstream: "pagination_token"),
    stringParam("granularity")
]

private let analyticsTimeParameters = [
    stringArrayParam("postIds", upstream: "ids", required: true, maximum: 100),
    stringParam("startTime", upstream: "start_time", required: true),
    stringParam("endTime", upstream: "end_time", required: true),
    stringParam("granularity", required: true)
]

private let openAPIParityQueryDefinitions: [OpenAPIParityDefinition] = [
    get("complianceJobs", "/2/compliance/jobs", query: [
        stringParam("type"),
        stringParam("status")
    ]),
    get("complianceJob", "/2/compliance/jobs/{id}", path: ["id"]),
    get("communitiesSearch", "/2/communities/search", query: [
        stringParam("query", required: true),
        intParam("maxResults", upstream: "max_results", defaultValue: nil, minimum: 1, maximum: 100),
        stringParam("nextToken", upstream: "next_token")
    ]),
    get("community", "/2/communities/{id}", path: ["id"]),
    get("communityNotesWritten", "/2/notes/search/notes_written", query: [
        boolParam("testMode", upstream: "test_mode", required: false, defaultValue: true)
    ] + commonPageParameters),
    get("communityPostsEligibleForNotes", "/2/notes/search/posts_eligible_for_notes", query: [
        boolParam("testMode", upstream: "test_mode", required: false, defaultValue: true),
        stringParam("postSelection", upstream: "post_selection")
    ] + commonPageParameters),
    get("communityNote", "/2/notes/{id}", path: ["id"]),
    get("allPostCounts", "/2/tweets/counts/all", query: countQueryParameters),
    get("postAnalytics", "/2/tweets/analytics", query: analyticsTimeParameters),
    get("postReposts", "/2/tweets/{postId}/retweets", path: ["postId"], query: commonPageParameters),
    get("media", "/2/media", query: [
        stringArrayParam("mediaKeys", upstream: "media_keys", required: true, maximum: 100)
    ]),
    get("mediaByKey", "/2/media/{mediaKey}", path: ["mediaKey"]),
    get("mediaAnalytics", "/2/media/analytics", query: [
        stringArrayParam("mediaKeys", upstream: "media_keys", required: true, maximum: 100),
        stringParam("startTime", upstream: "start_time", required: true),
        stringParam("endTime", upstream: "end_time", required: true),
        stringParam("granularity", required: true)
    ]),
    get("mediaUploadStatus", "/2/media/upload", query: [
        stringParam("mediaId", upstream: "media_id", required: true)
    ]),
    get("insights28hr", "/2/insights/28hr", query: [
        stringArrayParam("postIds", upstream: "tweet_ids", required: true, maximum: 100),
        stringParam("granularity", required: true),
        stringArrayParam("requestedMetrics", upstream: "requested_metrics", required: true, maximum: 50)
    ]),
    get("insightsHistorical", "/2/insights/historical", query: [
        stringArrayParam("postIds", upstream: "tweet_ids", required: true, maximum: 100),
        stringParam("startTime", upstream: "start_time", required: true),
        stringParam("endTime", upstream: "end_time", required: true),
        stringParam("granularity", required: true),
        stringArrayParam("requestedMetrics", upstream: "requested_metrics", required: true, maximum: 50)
    ]),
    get("personalizedTrends", "/2/users/personalized_trends"),
    get("publicKeys", "/2/users/public_keys", query: [
        stringArrayParam("userIds", upstream: "ids", required: true, maximum: 100)
    ]),
    get("userPublicKeys", "/2/users/{userId}/public_keys", path: ["userId"]),
    get("userAffiliates", "/2/users/{userId}/affiliates", path: ["userId"], query: commonPageParameters),
    get("repostsOfMe", "/2/users/reposts_of_me", query: commonPageParameters),
    get("webhooks", "/2/webhooks"),
    get("accountActivitySubscriptionCount", "/2/account_activity/subscriptions/count"),
    get("accountActivitySubscriptions", "/2/account_activity/webhooks/{webhookId}/subscriptions/all/list", path: ["webhookId"]),
    get("validateAccountActivitySubscription", "/2/account_activity/webhooks/{webhookId}/subscriptions/all", path: ["webhookId"]),
    get("activitySubscriptions", "/2/activity/subscriptions"),
    get("openAPISpec", "/2/openapi.json"),
    get("chatConversations", "/2/chat/conversations", query: commonPageParameters),
    get("chatConversation", "/2/chat/conversations/{id}", path: ["id"]),
    get("chatConversationEvents", "/2/chat/conversations/{id}/events", path: ["id"], query: commonPageParameters)
]

private let openAPIParityMutationDefinitions: [OpenAPIParityDefinition] = [
    post("createComplianceJob", "/2/compliance/jobs", body: [
        stringParam("type", required: true),
        stringParam("name", required: true),
        boolParam("resumable")
    ]),
    post("createCommunityNote", "/2/notes", body: [
        stringParam("postId", required: true),
        stringParam("classification", required: true),
        stringParam("text", required: true),
        boolParam("testMode")
    ], bodyBuilder: communityNoteBody),
    delete("deleteCommunityNote", "/2/notes/{id}", path: ["id"]),
    post("evaluateCommunityNote", "/2/evaluate_note", body: [
        stringParam("postId", upstream: "post_id", required: true),
        stringParam("noteText", upstream: "note_text", required: true)
    ]),
    put("hideReply", "/2/tweets/{postId}/hidden", path: ["postId"], body: [
        boolParam("hidden", required: true)
    ]),
    post("blockDirectMessages", "/2/users/{userId}/dm/block", path: ["userId"]),
    post("unblockDirectMessages", "/2/users/{userId}/dm/unblock", path: ["userId"]),
    post("initializeMediaUpload", "/2/media/upload/initialize", body: [
        stringParam("mediaType", upstream: "media_type", required: true),
        intParam("totalBytes", upstream: "total_bytes", required: true, minimum: 1, maximum: Int.max),
        stringParam("mediaCategory", upstream: "media_category")
    ]),
    post("finalizeMediaUpload", "/2/media/upload/{mediaId}/finalize", path: ["mediaId"]),
    post("createMediaMetadata", "/2/media/metadata", body: [
        stringParam("mediaId", required: true),
        stringParam("altText", required: true)
    ], bodyBuilder: mediaMetadataBody),
    post("createMediaSubtitles", "/2/media/subtitles", body: [
        stringParam("mediaId", required: true),
        stringParam("mediaCategory"),
        stringParam("languageCode", required: true),
        stringParam("displayName", required: true),
        stringParam("filePath", required: true)
    ], bodyBuilder: mediaSubtitlesBody),
    delete("deleteMediaSubtitles", "/2/media/subtitles", body: [
        stringParam("mediaId", upstream: "id", required: true),
        stringParam("languageCode", upstream: "language_code", required: true)
    ]),
    post("createWebhook", "/2/webhooks", body: [
        stringParam("url", required: true)
    ]),
    delete("deleteWebhook", "/2/webhooks/{webhookId}", path: ["webhookId"]),
    put("validateWebhook", "/2/webhooks/{webhookId}", path: ["webhookId"]),
    post("replayWebhook", "/2/webhooks/replay", body: [
        stringParam("webhookId", upstream: "webhook_id", required: true),
        stringParam("fromDate", upstream: "from_date", required: true),
        stringParam("toDate", upstream: "to_date", required: true)
    ]),
    post("createAccountActivitySubscription", "/2/account_activity/webhooks/{webhookId}/subscriptions/all", path: ["webhookId"]),
    delete("deleteAccountActivitySubscription", "/2/account_activity/webhooks/{webhookId}/subscriptions/{userId}/all", path: ["webhookId", "userId"]),
    post("createActivitySubscription", "/2/activity/subscriptions", body: [
        stringParam("eventType", upstream: "event_type", required: true),
        stringParam("filter", required: true),
        stringParam("tag"),
        stringParam("webhookId", upstream: "webhook_id")
    ]),
    put("updateActivitySubscription", "/2/activity/subscriptions/{subscriptionId}", path: ["subscriptionId"], body: [
        stringParam("eventType", upstream: "event_type"),
        stringParam("filter"),
        stringParam("tag"),
        stringParam("webhookId", upstream: "webhook_id")
    ]),
    delete("deleteActivitySubscription", "/2/activity/subscriptions/{subscriptionId}", path: ["subscriptionId"]),
    delete("deleteActivitySubscriptions", "/2/activity/subscriptions", query: [
        stringArrayParam("subscriptionIds", upstream: "ids", required: true, maximum: 100)
    ]),
    post("initializeChatConversationKeys", "/2/chat/conversations/{id}/keys", path: ["id"]),
    post("markChatConversationRead", "/2/chat/conversations/{id}/read", path: ["id"]),
    post("sendChatTypingIndicator", "/2/chat/conversations/{id}/typing", path: ["id"]),
    post("sendEncryptedChatMessage", "/2/chat/conversations/{id}/messages", path: ["id"], body: [
        stringParam("messageId", upstream: "message_id", required: true),
        stringParam("encodedMessageCreateEvent", upstream: "encoded_message_create_event", required: true),
        stringParam("encodedMessageEventSignature", upstream: "encoded_message_event_signature"),
        stringParam("conversationToken", upstream: "conversation_token")
    ]),
    post("addChatGroupMembers", "/2/chat/conversations/{id}/members", path: ["id"], body: [
        stringArrayParam("participantIds", upstream: "user_ids", required: true, maximum: 100)
    ]),
    post("addUserPublicKey", "/2/users/{userId}/public_keys", path: ["userId"], body: [
        stringParam("version", required: true),
        stringParam("publicKey", required: true),
        stringParam("signingPublicKey", required: true),
        stringParam("identityPublicKeySignature"),
        stringParam("signingPublicKeySignature"),
        stringParam("publicKeyFingerprint"),
        stringParam("registrationMethod"),
        boolParam("generateVersion")
    ], bodyBuilder: publicKeyBody),
    post("createEncryptedChatGroupConversation", "/2/chat/conversations/group", body: [
        stringParam("conversationId", required: true),
        stringParam("conversationKeyVersion", required: true),
        stringParam("conversationParticipantKeysJSON", required: true),
        stringArrayParam("groupMembers", required: true, maximum: 100),
        stringParam("actionSignaturesJSON"),
        stringParam("base64EncodedKeyRotation"),
        stringArrayParam("groupAdmins", required: false, maximum: 100),
        stringParam("groupName"),
        stringParam("groupDescription"),
        stringParam("groupAvatarUrl"),
        stringParam("ttlMsec")
    ], bodyBuilder: encryptedChatGroupBody),
    post("initializeChatGroup", "/2/chat/conversations/group/initialize"),
    post("initializeChatMediaUpload", "/2/chat/media/upload/initialize", body: [
        stringParam("conversationId", upstream: "conversation_id", required: true),
        intParam("totalBytes", upstream: "total_bytes", required: true, minimum: 0, maximum: Int.max)
    ]),
    post("finalizeChatMediaUpload", "/2/chat/media/upload/{id}/finalize", path: ["id"], body: [
        stringParam("conversationId", upstream: "conversation_id", required: true),
        stringParam("mediaHashKey", upstream: "media_hash_key", required: true),
        stringParam("messageId", upstream: "message_id"),
        stringParam("numParts", upstream: "num_parts"),
        stringParam("ttlMsec", upstream: "ttl_msec")
    ])
]

func parseOpenAPIParityQueryOperation(fieldName: String?, arguments: String) throws -> SupportedGraphQLOperation? {
    guard let definition = openAPIParityQueryDefinitions.first(where: { $0.fieldName == fieldName }) else {
        return nil
    }
    return .openAPIQuery(try buildOpenAPIParityRequest(definition: definition, arguments: arguments))
}

func parseOpenAPIParityMutationOperation(fieldName: String?, arguments: String) throws -> SupportedGraphQLOperation? {
    guard let definition = openAPIParityMutationDefinitions.first(where: { $0.fieldName == fieldName }) else {
        return nil
    }
    return .openAPIMutation(try buildOpenAPIParityRequest(definition: definition, arguments: arguments))
}

private func buildOpenAPIParityRequest(definition: OpenAPIParityDefinition, arguments: String) throws -> OpenAPIParityRequest {
    let allowed = Set(
        definition.pathParameters
            + definition.queryParameters.map(\.graphQLName)
            + definition.bodyParameters.map(\.graphQLName)
    )
    try validateGraphQLArguments(in: arguments, allowed: allowed, fieldName: definition.fieldName)
    let path = try resolveOpenAPIPath(definition.pathTemplate, parameters: definition.pathParameters, arguments: arguments, fieldName: definition.fieldName)
    let query = try Dictionary(uniqueKeysWithValues: definition.queryParameters.compactMap { parameter in
        try openAPIParameterValue(parameter, from: arguments, fieldName: definition.fieldName).map { (parameter.upstreamName, $0) }
    })
    let body: [String: Any]?
    if let bodyBuilder = definition.bodyBuilder {
        body = try bodyBuilder(arguments, definition.fieldName)
    } else {
        body = try openAPIBody(parameters: definition.bodyParameters, arguments: arguments, fieldName: definition.fieldName)
    }
    return OpenAPIParityRequest(fieldName: definition.fieldName, method: definition.method, path: path, query: query, body: body)
}

private func resolveOpenAPIPath(_ template: String, parameters: [String], arguments: String, fieldName: String) throws -> String {
    var path = template
    for parameter in parameters {
        let value = try extractStringArgument(parameter, from: arguments, fieldName: fieldName)
        path = path.replacingOccurrences(of: "{\(parameter)}", with: urlPathEscape(value))
    }
    return path
}

private func openAPIBody(parameters: [OpenAPIParityParameter], arguments: String, fieldName: String) throws -> [String: Any]? {
    let pairs = try parameters.compactMap { parameter -> (String, Any)? in
        guard let value = try openAPIAnyValue(parameter, from: arguments, fieldName: fieldName) else {
            return nil
        }
        return (parameter.upstreamName, value)
    }
    return pairs.isEmpty ? nil : Dictionary(uniqueKeysWithValues: pairs)
}

private func openAPIParameterValue(_ parameter: OpenAPIParityParameter, from arguments: String, fieldName: String) throws -> String? {
    guard let value = try openAPIAnyValue(parameter, from: arguments, fieldName: fieldName) else {
        return nil
    }
    if let strings = value as? [String] {
        return strings.joined(separator: ",")
    }
    return String(describing: value)
}

private func openAPIAnyValue(_ parameter: OpenAPIParityParameter, from arguments: String, fieldName: String) throws -> Any? {
    switch parameter.kind {
    case .string(let required):
        if required {
            return try extractStringArgument(parameter.graphQLName, from: arguments, fieldName: fieldName)
        }
        return try extractOptionalStringArgument(parameter.graphQLName, from: arguments, fieldName: fieldName)
    case .stringArray(let required, let maximum):
        if required {
            return try extractStringArrayArgument(parameter.graphQLName, from: arguments, fieldName: fieldName, maximum: maximum)
        }
        return try extractOptionalStringArrayArgument(parameter.graphQLName, from: arguments, fieldName: fieldName, maximum: maximum)
    case .int(let required, let defaultValue, let minimum, let maximum):
        if required {
            return try extractRequiredIntArgument(parameter.graphQLName, from: arguments, minimum: minimum, maximum: maximum, fieldName: fieldName)
        }
        guard rangeOfGraphQLArgument(parameter.graphQLName, in: arguments) != nil else {
            return defaultValue
        }
        return try extractOptionalIntArgument(parameter.graphQLName, from: arguments, defaultValue: defaultValue ?? minimum, minimum: minimum, maximum: maximum, fieldName: fieldName)
    case .bool(let required, let defaultValue):
        if required {
            guard rangeOfGraphQLArgument(parameter.graphQLName, in: arguments) != nil else {
                throw validation("\(fieldName) requires \(parameter.graphQLName).")
            }
            return try extractOptionalBoolArgument(parameter.graphQLName, from: arguments, defaultValue: false, fieldName: fieldName)
        }
        guard rangeOfGraphQLArgument(parameter.graphQLName, in: arguments) != nil else {
            return defaultValue
        }
        return try extractOptionalBoolArgument(parameter.graphQLName, from: arguments, defaultValue: defaultValue ?? false, fieldName: fieldName)
    }
}

private func communityNoteBody(arguments: String, fieldName: String) throws -> [String: Any] {
    return [
        "post_id": try extractStringArgument("postId", from: arguments, fieldName: fieldName),
        "test_mode": try extractOptionalBoolArgument("testMode", from: arguments, defaultValue: true, fieldName: fieldName),
        "info": [
            "classification": try extractStringArgument("classification", from: arguments, fieldName: fieldName),
            "text": try extractStringArgument("text", from: arguments, fieldName: fieldName)
        ]
    ]
}

private func mediaMetadataBody(arguments: String, fieldName: String) throws -> [String: Any] {
    return [
        "id": try extractStringArgument("mediaId", from: arguments, fieldName: fieldName),
        "metadata": [
            "alt_text": try extractStringArgument("altText", from: arguments, fieldName: fieldName)
        ]
    ]
}

private func mediaSubtitlesBody(arguments: String, fieldName: String) throws -> [String: Any] {
    return [
        "id": try extractStringArgument("mediaId", from: arguments, fieldName: fieldName),
        "media_category": try extractOptionalStringArgument("mediaCategory", from: arguments, fieldName: fieldName) ?? "tweet_video",
        "subtitles": [
            [
                "language_code": try extractStringArgument("languageCode", from: arguments, fieldName: fieldName),
                "display_name": try extractStringArgument("displayName", from: arguments, fieldName: fieldName),
                "file_name": try extractStringArgument("filePath", from: arguments, fieldName: fieldName)
            ]
        ]
    ]
}

private func publicKeyBody(arguments: String, fieldName: String) throws -> [String: Any] {
    var publicKey: [String: Any] = [
        "public_key": try extractStringArgument("publicKey", from: arguments, fieldName: fieldName),
        "signing_public_key": try extractStringArgument("signingPublicKey", from: arguments, fieldName: fieldName)
    ]
    try copyOptionalStringArgument("identityPublicKeySignature", upstream: "identity_public_key_signature", from: arguments, fieldName: fieldName, into: &publicKey)
    try copyOptionalStringArgument("signingPublicKeySignature", upstream: "signing_public_key_signature", from: arguments, fieldName: fieldName, into: &publicKey)
    try copyOptionalStringArgument("publicKeyFingerprint", upstream: "public_key_fingerprint", from: arguments, fieldName: fieldName, into: &publicKey)
    try copyOptionalStringArgument("registrationMethod", upstream: "registration_method", from: arguments, fieldName: fieldName, into: &publicKey)
    var body: [String: Any] = [
        "version": try extractStringArgument("version", from: arguments, fieldName: fieldName),
        "public_key": publicKey
    ]
    if let generateVersion = try openAPIOptionalBoolArgument("generateVersion", from: arguments, fieldName: fieldName) {
        body["generate_version"] = generateVersion
    }
    return body
}

private func encryptedChatGroupBody(arguments: String, fieldName: String) throws -> [String: Any] {
    var body: [String: Any] = [
        "conversation_id": try extractStringArgument("conversationId", from: arguments, fieldName: fieldName),
        "conversation_key_version": try extractStringArgument("conversationKeyVersion", from: arguments, fieldName: fieldName),
        "conversation_participant_keys": try jsonArgument("conversationParticipantKeysJSON", from: arguments, fieldName: fieldName),
        "group_members": try extractStringArrayArgument("groupMembers", from: arguments, fieldName: fieldName, maximum: 100)
    ]
    if let signatures = try optionalJSONArgument("actionSignaturesJSON", from: arguments, fieldName: fieldName) {
        body["action_signatures"] = signatures
    }
    try copyOptionalStringArgument("base64EncodedKeyRotation", upstream: "base64_encoded_key_rotation", from: arguments, fieldName: fieldName, into: &body)
    if let groupAdmins = try extractOptionalStringArrayArgument("groupAdmins", from: arguments, fieldName: fieldName, maximum: 100) {
        body["group_admins"] = groupAdmins
    }
    try copyOptionalStringArgument("groupName", upstream: "group_name", from: arguments, fieldName: fieldName, into: &body)
    try copyOptionalStringArgument("groupDescription", upstream: "group_description", from: arguments, fieldName: fieldName, into: &body)
    try copyOptionalStringArgument("groupAvatarUrl", upstream: "group_avatar_url", from: arguments, fieldName: fieldName, into: &body)
    try copyOptionalStringArgument("ttlMsec", upstream: "ttl_msec", from: arguments, fieldName: fieldName, into: &body)
    return body
}

private func copyOptionalStringArgument(
    _ graphQLName: String,
    upstream: String,
    from arguments: String,
    fieldName: String,
    into body: inout [String: Any]
) throws {
    if let value = try extractOptionalStringArgument(graphQLName, from: arguments, fieldName: fieldName) {
        body[upstream] = value
    }
}

private func openAPIOptionalBoolArgument(_ name: String, from arguments: String, fieldName: String) throws -> Bool? {
    guard rangeOfGraphQLArgument(name, in: arguments) != nil else {
        return nil
    }
    return try extractOptionalBoolArgument(name, from: arguments, defaultValue: false, fieldName: fieldName)
}

private func optionalJSONArgument(_ name: String, from arguments: String, fieldName: String) throws -> Any? {
    guard rangeOfGraphQLArgument(name, in: arguments) != nil else {
        return nil
    }
    return try jsonArgument(name, from: arguments, fieldName: fieldName)
}

private func jsonArgument(_ name: String, from arguments: String, fieldName: String) throws -> Any {
    let value = try extractStringArgument(name, from: arguments, fieldName: fieldName)
    guard let data = value.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data, options: []),
          JSONSerialization.isValidJSONObject(object) else {
        throw validation("\(fieldName).\(name) must be a JSON object or array string.")
    }
    return object
}

private func get(
    _ fieldName: String,
    _ pathTemplate: String,
    path: [String] = [],
    query: [OpenAPIParityParameter] = []
) -> OpenAPIParityDefinition {
    return definition(fieldName, "GET", pathTemplate, path: path, query: query)
}

private func post(
    _ fieldName: String,
    _ pathTemplate: String,
    path: [String] = [],
    query: [OpenAPIParityParameter] = [],
    body: [OpenAPIParityParameter] = [],
    bodyBuilder: ((String, String) throws -> [String: Any]?)? = nil
) -> OpenAPIParityDefinition {
    return definition(fieldName, "POST", pathTemplate, path: path, query: query, body: body, bodyBuilder: bodyBuilder)
}

private func put(
    _ fieldName: String,
    _ pathTemplate: String,
    path: [String] = [],
    query: [OpenAPIParityParameter] = [],
    body: [OpenAPIParityParameter] = []
) -> OpenAPIParityDefinition {
    return definition(fieldName, "PUT", pathTemplate, path: path, query: query, body: body)
}

private func delete(
    _ fieldName: String,
    _ pathTemplate: String,
    path: [String] = [],
    query: [OpenAPIParityParameter] = [],
    body: [OpenAPIParityParameter] = []
) -> OpenAPIParityDefinition {
    return definition(fieldName, "DELETE", pathTemplate, path: path, query: query, body: body)
}

private func definition(
    _ fieldName: String,
    _ method: String,
    _ pathTemplate: String,
    path: [String] = [],
    query: [OpenAPIParityParameter] = [],
    body: [OpenAPIParityParameter] = [],
    bodyBuilder: ((String, String) throws -> [String: Any]?)? = nil
) -> OpenAPIParityDefinition {
    return OpenAPIParityDefinition(
        fieldName: fieldName,
        method: method,
        pathTemplate: pathTemplate,
        pathParameters: path,
        queryParameters: query,
        bodyParameters: body,
        bodyBuilder: bodyBuilder
    )
}

private func stringParam(_ graphQLName: String, upstream: String? = nil, required: Bool = false) -> OpenAPIParityParameter {
    return OpenAPIParityParameter(graphQLName: graphQLName, upstreamName: upstream ?? graphQLName, kind: .string(required: required))
}

private func stringArrayParam(_ graphQLName: String, upstream: String? = nil, required: Bool = false, maximum: Int) -> OpenAPIParityParameter {
    return OpenAPIParityParameter(graphQLName: graphQLName, upstreamName: upstream ?? graphQLName, kind: .stringArray(required: required, maximum: maximum))
}

private func intParam(
    _ graphQLName: String,
    upstream: String? = nil,
    required: Bool = false,
    defaultValue: Int? = nil,
    minimum: Int,
    maximum: Int
) -> OpenAPIParityParameter {
    return OpenAPIParityParameter(
        graphQLName: graphQLName,
        upstreamName: upstream ?? graphQLName,
        kind: .int(required: required, defaultValue: defaultValue, minimum: minimum, maximum: maximum)
    )
}

private func boolParam(_ graphQLName: String, upstream: String? = nil, required: Bool = false, defaultValue: Bool? = nil) -> OpenAPIParityParameter {
    return OpenAPIParityParameter(graphQLName: graphQLName, upstreamName: upstream ?? graphQLName, kind: .bool(required: required, defaultValue: defaultValue))
}
