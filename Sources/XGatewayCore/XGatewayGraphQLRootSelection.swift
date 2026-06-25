func resolveSupportedGraphQLRootOperation(
    in document: String,
    operationType: XGatewayGraphQLOperationType
) throws -> ResolvedGraphQLRootOperation {
    try validateSingleGraphQLExecutableDocument(in: document)

    let supportedFields: [String]
    switch operationType {
    case .query:
        supportedFields = supportedQueryGraphQLFields
    case .mutation:
        supportedFields = supportedMutationGraphQLFields
    }
    let supported = Set(supportedFields)

    if let rootSelection = try graphQLRootSelectionLiteral(in: document, operationType: operationType) {
        let rootFields = try graphQLRootFields(in: rootSelection)
        if rootFields.isEmpty {
            throw validation("Public GraphQL requests support exactly one top-level field; found none.")
        }
        if rootFields.count > 1 {
            throw validation("Public GraphQL requests support exactly one top-level field; found \(rootFields.map(\.name).joined(separator: ", ")).")
        }
        if let field = rootFields.first,
           supported.contains(field.name) {
            return ResolvedGraphQLRootOperation(fieldName: field.name, argumentLiteral: field.argumentLiteral)
        }
        return ResolvedGraphQLRootOperation(fieldName: nil, argumentLiteral: "")
    }

    if let field = supportedFields.first(where: { hasGraphQLField($0, in: document) }) {
        return ResolvedGraphQLRootOperation(
            fieldName: field,
            argumentLiteral: try graphQLFieldArgumentLiteral(field, in: document)
        )
    }
    return ResolvedGraphQLRootOperation(fieldName: nil, argumentLiteral: "")
}

private func validateSingleGraphQLExecutableDocument(in source: String) throws {
    var operationDefinitionCount = 0
    var index = skipGraphQLIgnored(in: source, from: source.startIndex)
    while index < source.endIndex {
        if let nextIndex = indexAfterGraphQLComment(in: source, from: index) {
            index = skipGraphQLIgnored(in: source, from: nextIndex)
            continue
        }
        if source[index] == "{" {
            operationDefinitionCount += 1
            try validateSingleGraphQLOperationDefinitionCount(operationDefinitionCount)
            index = try extractBalancedLiteral(
                from: source,
                startingAt: index,
                opening: "{",
                closing: "}",
                context: "anonymous query selection"
            ).nextIndex
            index = skipGraphQLIgnored(in: source, from: index)
            continue
        }
        guard isGraphQLNameStart(source[index]) else {
            throw validation("Unexpected GraphQL token '\(source[index])' outside the operation definition. Public GraphQL requests support exactly one query or mutation operation definition.")
        }

        let start = index
        index = source.index(after: index)
        while index < source.endIndex,
              isGraphQLIdentifierCharacter(source[index]) {
            index = source.index(after: index)
        }
        let token = String(source[start..<index])
        if token == "fragment" {
            throw validation("Public GraphQL fragments are not supported yet.")
        }
        if token == "subscription" {
            throw validation("Public GraphQL subscriptions are not supported.")
        }
        if token == "query" || token == "mutation" {
            operationDefinitionCount += 1
            try validateSingleGraphQLOperationDefinitionCount(operationDefinitionCount)
            index = try indexAfterGraphQLOperationDefinition(
                in: source,
                from: index,
                operationLabel: token
            )
            index = skipGraphQLIgnored(in: source, from: index)
            continue
        }
        throw validation("Unexpected GraphQL token '\(token)' outside the operation definition. Public GraphQL requests support exactly one query or mutation operation definition.")
    }
}

private func validateSingleGraphQLOperationDefinitionCount(_ count: Int) throws {
    if count > 1 {
        throw validation("Public GraphQL requests support exactly one operation definition.")
    }
}

func hasGraphQLField(_ name: String, in source: String) -> Bool {
    return rangeOfGraphQLField(name, in: source) != nil
}

func graphQLSelectionLiteral(
    in document: String,
    operationType: XGatewayGraphQLOperationType,
    selectionPath: String
) throws -> String? {
    guard let rootSelection = try graphQLRootSelectionLiteral(in: document, operationType: operationType) else {
        return nil
    }

    var selectionLiteral = rootSelection
    for fieldName in selectionPath.split(separator: ".").map(String.init) {
        guard let field = try graphQLRootFields(in: selectionLiteral).first(where: { $0.name == fieldName }),
              let childSelection = field.selectionLiteral else {
            return nil
        }
        selectionLiteral = childSelection
    }
    return selectionLiteral
}

private func graphQLRootSelectionLiteral(
    in source: String,
    operationType: XGatewayGraphQLOperationType
) throws -> String? {
    let firstToken = skipGraphQLIgnored(in: source, from: source.startIndex)
    if operationType == .query,
       firstToken < source.endIndex,
       source[firstToken] == "{" {
        return try extractBalancedLiteral(
            from: source,
            startingAt: firstToken,
            opening: "{",
            closing: "}",
            context: "root selection"
        ).literal
    }

    var inString = false
    var escaping = false
    var index = firstToken

    while index < source.endIndex {
        let character = source[index]
        if inString {
            if escaping {
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "\"" {
                inString = false
            }
            index = source.index(after: index)
            continue
        }

        if character == "\"" {
            inString = true
            index = source.index(after: index)
            continue
        }
        if let nextIndex = indexAfterGraphQLComment(in: source, from: index) {
            index = nextIndex
            continue
        }
        if character == "{" {
            index = try extractBalancedLiteral(
                from: source,
                startingAt: index,
                opening: "{",
                closing: "}",
                context: "non-operation selection"
            ).nextIndex
            continue
        }
        guard isGraphQLNameStart(character) else {
            index = source.index(after: index)
            continue
        }

        let start = index
        index = source.index(after: index)
        while index < source.endIndex,
              isGraphQLIdentifierCharacter(source[index]) {
            index = source.index(after: index)
        }
        if source[start..<index] == operationType.rawValue[...] {
            if let rootSelection = try graphQLOperationRootSelection(
                in: source,
                from: index,
                operationLabel: operationType.rawValue
            )?.literal {
                return rootSelection
            }
        }
    }

    return nil
}

private func indexAfterGraphQLOperationDefinition(
    in source: String,
    from keywordEnd: String.Index,
    operationLabel: String
) throws -> String.Index {
    return try graphQLOperationRootSelection(
        in: source,
        from: keywordEnd,
        operationLabel: operationLabel
    )?.nextIndex ?? keywordEnd
}

private func graphQLOperationRootSelection(
    in source: String,
    from keywordEnd: String.Index,
    operationLabel: String
) throws -> (literal: String, nextIndex: String.Index)? {
    var index = skipGraphQLIgnored(in: source, from: keywordEnd)
    if index < source.endIndex,
       isGraphQLNameStart(source[index]) {
        index = source.index(after: index)
        while index < source.endIndex,
              isGraphQLIdentifierCharacter(source[index]) {
            index = source.index(after: index)
        }
        index = skipGraphQLIgnored(in: source, from: index)
    }
    if index < source.endIndex,
       source[index] == "(" {
        index = try extractBalancedLiteral(
            from: source,
            startingAt: index,
            opening: "(",
            closing: ")",
            context: "\(operationLabel) variable definitions"
        ).nextIndex
    }
    index = try rejectGraphQLDirectivesIfPresent(in: source, from: index)
    index = skipGraphQLIgnored(in: source, from: index)
    guard index < source.endIndex,
          source[index] == "{" else {
        return nil
    }
    return try extractBalancedLiteral(
        from: source,
        startingAt: index,
        opening: "{",
        closing: "}",
        context: "root selection"
    )
}

func graphQLRootFields(in selectionLiteral: String) throws -> [GraphQLRootField] {
    var fields: [GraphQLRootField] = []
    var inString = false
    var escaping = false
    var depth = 0
    var index = selectionLiteral.startIndex

    while index < selectionLiteral.endIndex {
        let character = selectionLiteral[index]
        if inString {
            if escaping {
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "\"" {
                inString = false
            }
            index = selectionLiteral.index(after: index)
            continue
        }

        if character == "\"" {
            inString = true
            index = selectionLiteral.index(after: index)
            continue
        }
        if let nextIndex = indexAfterGraphQLComment(in: selectionLiteral, from: index) {
            index = nextIndex
            continue
        }
        if selectionLiteral[index...].hasPrefix("...") {
            throw validation("Public GraphQL fragments are not supported yet.")
        }
        if character == "@" {
            throw validation("Public GraphQL directives are not supported yet.")
        }
        if character == "{" {
            depth += 1
            index = selectionLiteral.index(after: index)
            continue
        }
        if character == "}" {
            depth -= 1
            index = selectionLiteral.index(after: index)
            continue
        }
        guard depth == 1,
              isGraphQLNameStart(character) else {
            index = selectionLiteral.index(after: index)
            continue
        }

        let firstNameStart = index
        index = selectionLiteral.index(after: index)
        while index < selectionLiteral.endIndex,
              isGraphQLIdentifierCharacter(selectionLiteral[index]) {
            index = selectionLiteral.index(after: index)
        }
        if firstNameStart > selectionLiteral.startIndex,
           selectionLiteral[selectionLiteral.index(before: firstNameStart)] == "@" {
            throw validation("Public GraphQL directives are not supported yet.")
        }
        if firstNameStart > selectionLiteral.startIndex,
           selectionLiteral[selectionLiteral.index(before: firstNameStart)] == "$" {
            continue
        }
        let hasFragmentSpread = hasGraphQLFragmentSpreadBeforeName(in: selectionLiteral, before: firstNameStart)
        if hasFragmentSpread {
            throw validation("Public GraphQL fragments are not supported yet.")
        }
        let fieldName = String(selectionLiteral[firstNameStart..<index])
        let afterFirstName = skipGraphQLIgnored(in: selectionLiteral, from: index)
        if afterFirstName < selectionLiteral.endIndex,
           selectionLiteral[afterFirstName] == ":" {
            throw validation("Public GraphQL aliases are not supported yet.")
        }
        let tail = try skipGraphQLRootFieldTail(in: selectionLiteral, from: index)
        fields.append(
            GraphQLRootField(
                name: fieldName,
                argumentLiteral: tail.argumentLiteral,
                selectionLiteral: tail.selectionLiteral
            )
        )
        index = tail.nextIndex
    }

    return fields
}

private struct GraphQLFieldTail {
    let argumentLiteral: String
    let selectionLiteral: String?
    let nextIndex: String.Index
}

private func skipGraphQLRootFieldTail(
    in selectionLiteral: String,
    from startIndex: String.Index
) throws -> GraphQLFieldTail {
    var index = skipGraphQLIgnored(in: selectionLiteral, from: startIndex)
    var argumentLiteral = ""
    if index < selectionLiteral.endIndex,
       selectionLiteral[index] == "(" {
        let extracted = try extractBalancedLiteral(
            from: selectionLiteral,
            startingAt: index,
            opening: "(",
            closing: ")",
            context: "root field arguments"
        )
        argumentLiteral = extracted.literal
        index = extracted.nextIndex
    }
    index = try rejectGraphQLDirectivesIfPresent(in: selectionLiteral, from: index)

    let selectionStart = skipGraphQLIgnored(in: selectionLiteral, from: index)
    guard selectionStart < selectionLiteral.endIndex,
          selectionLiteral[selectionStart] == "{" else {
        return GraphQLFieldTail(
            argumentLiteral: argumentLiteral,
            selectionLiteral: nil,
            nextIndex: selectionStart
        )
    }

    let extractedSelection = try extractBalancedLiteral(
        from: selectionLiteral,
        startingAt: selectionStart,
        opening: "{",
        closing: "}",
        context: "field selection"
    )
    _ = try graphQLRootFields(in: extractedSelection.literal)
    return GraphQLFieldTail(
        argumentLiteral: argumentLiteral,
        selectionLiteral: extractedSelection.literal,
        nextIndex: extractedSelection.nextIndex
    )
}

private func rejectGraphQLDirectivesIfPresent(in selectionLiteral: String, from startIndex: String.Index) throws -> String.Index {
    let index = skipGraphQLIgnored(in: selectionLiteral, from: startIndex)
    if index < selectionLiteral.endIndex,
       selectionLiteral[index] == "@" {
        throw validation("Public GraphQL directives are not supported yet.")
    }
    return index
}

func graphQLFieldArgumentLiteral(_ name: String, in source: String) throws -> String {
    guard let fieldRange = rangeOfGraphQLField(name, in: source) else {
        throw validation("Public GraphQL field '\(name)' was not found.")
    }
    let index = skipGraphQLIgnored(in: source, from: fieldRange.upperBound)
    guard index < source.endIndex,
          source[index] == "(" else {
        return ""
    }
    return try extractBalancedLiteral(
        from: source,
        startingAt: index,
        opening: "(",
        closing: ")",
        context: "\(name) arguments"
    ).literal
}
