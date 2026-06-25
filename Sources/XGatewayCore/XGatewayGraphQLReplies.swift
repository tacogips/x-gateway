private let supportedGraphQLReplyArguments = GraphQLArgumentSet.pagedPostReadOptions

func extractReplyExpansion(
    from document: String,
    operationType: XGatewayGraphQLOperationType,
    selectionPath: String
) throws -> ReplyExpansionRequest? {
    guard let selectionLiteral = try graphQLSelectionLiteral(
        in: document,
        operationType: operationType,
        selectionPath: selectionPath
    ) else {
        return nil
    }
    return try extractReplyExpansion(fromPostSelection: selectionLiteral, selectionPath: selectionPath)
}

private func extractReplyExpansion(
    fromPostSelection selectionLiteral: String,
    selectionPath: String
) throws -> ReplyExpansionRequest? {
    guard let repliesField = try graphQLRootFields(in: selectionLiteral).first(where: { $0.name == "replies" }) else {
        return nil
    }

    let argumentLiteral = repliesField.argumentLiteral

    for argumentName in graphQLArgumentNames(in: argumentLiteral) where !supportedGraphQLReplyArguments.contains(argumentName) {
        throw validation("Public GraphQL selection '\(selectionPath).replies' does not accept argument '\(argumentName)'.")
    }

    guard let repliesSelectionLiteral = repliesField.selectionLiteral else {
        throw validation("Public GraphQL selection '\(selectionPath).replies' must include a nested selection set.")
    }

    let childPostSelection = try graphQLRootFields(in: repliesSelectionLiteral)
        .first(where: { $0.name == "posts" })?
        .selectionLiteral
    let childExpansion: ReplyExpansionRequest?
    if let childPostSelection {
        childExpansion = try extractReplyExpansion(
            fromPostSelection: childPostSelection,
            selectionPath: "\(selectionPath).replies.posts"
        )
    } else {
        childExpansion = nil
    }

    return ReplyExpansionRequest(
        maxResults: try extractOptionalIntArgument("maxResults", from: argumentLiteral, defaultValue: 10, minimum: 10, maximum: 100, fieldName: "\(selectionPath).replies"),
        paginationToken: try extractOptionalStringArgument("paginationToken", from: argumentLiteral, fieldName: "\(selectionPath).replies"),
        readOptions: try extractPostReadOptions(from: argumentLiteral, fieldName: "\(selectionPath).replies"),
        child: childExpansion
    )
}
