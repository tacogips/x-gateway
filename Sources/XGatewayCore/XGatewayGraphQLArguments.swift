import Foundation

enum GraphQLArgumentSet {
    static let noArguments: Set<String> = []
    static let postReadOptions: Set<String> = [
        "mediaRootDir",
        "downloadMedia",
        "forceDownload",
        "includePromoted"
    ]
    static let pagedPostReadOptions = postReadOptions.union([
        "maxResults",
        "paginationToken"
    ])
}

func extractPostReadOptions(from document: String, fieldName: String) throws -> XGatewayPostReadOptions {
    return XGatewayPostReadOptions(
        mediaRootDir: try extractOptionalStringArgument("mediaRootDir", from: document, fieldName: fieldName),
        downloadMedia: try extractOptionalBoolArgument("downloadMedia", from: document, defaultValue: true, fieldName: fieldName),
        forceDownload: try extractOptionalBoolArgument("forceDownload", from: document, defaultValue: false, fieldName: fieldName),
        includePromoted: try extractOptionalBoolArgument("includePromoted", from: document, defaultValue: false, fieldName: fieldName)
    )
}

func validateGraphQLArguments(in argumentLiteral: String, allowed: Set<String>, fieldName: String) throws {
    for argumentName in graphQLArgumentNames(in: argumentLiteral) where !allowed.contains(argumentName) {
        throw validation("Public GraphQL field '\(fieldName)' does not accept argument '\(argumentName)'.")
    }
}

func rangeOfGraphQLArgument(_ name: String, in source: String) -> Range<String.Index>? {
    var inString = false
    var escaping = false
    var index = source.startIndex
    var nestingDepth = 0
    let targetDepth = graphQLTopLevelArgumentDepth(in: source)

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
        if character == "(" || character == "[" || character == "{" {
            nestingDepth += 1
            index = source.index(after: index)
            continue
        }
        if character == ")" || character == "]" || character == "}" {
            nestingDepth = max(0, nestingDepth - 1)
            index = source.index(after: index)
            continue
        }

        guard nestingDepth == targetDepth,
              isGraphQLNameStart(character) else {
            index = source.index(after: index)
            continue
        }

        let start = index
        index = source.index(after: index)
        while index < source.endIndex,
              isGraphQLIdentifierCharacter(source[index]) {
            index = source.index(after: index)
        }
        if source[start..<index] == name[...] {
            let colonIndex = skipGraphQLIgnored(in: source, from: index)
            if colonIndex < source.endIndex,
               source[colonIndex] == ":" {
                return start..<source.index(after: colonIndex)
            }
        }
    }

    return nil
}

func rangeOfGraphQLField(_ name: String, in source: String) -> Range<String.Index>? {
    var inString = false
    var escaping = false
    var index = source.startIndex
    var previousName: String?

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

        guard isGraphQLNameStart(character) else {
            if !isGraphQLWhitespace(character) {
                previousName = nil
            }
            index = source.index(after: index)
            continue
        }

        let start = index
        index = source.index(after: index)
        while index < source.endIndex,
              isGraphQLIdentifierCharacter(source[index]) {
            index = source.index(after: index)
        }
        let foundName = String(source[start..<index])
        if foundName == name {
            let afterName = skipGraphQLIgnored(in: source, from: index)
            let isAliasName = afterName < source.endIndex && source[afterName] == ":"
            let isDefinitionName = previousName == "query"
                || previousName == "mutation"
                || previousName == "subscription"
                || previousName == "fragment"
                || previousName == "on"
            let isDirectiveName = start > source.startIndex && source[source.index(before: start)] == "@"
            let isVariableName = start > source.startIndex && source[source.index(before: start)] == "$"
            let isFragmentSpreadName = hasGraphQLFragmentSpreadBeforeName(in: source, before: start)
            if !isAliasName && !isDefinitionName && !isDirectiveName && !isVariableName && !isFragmentSpreadName {
                return start..<index
            }
        }
        previousName = foundName
    }

    return nil
}

func graphQLArgumentNames(in argumentLiteral: String) -> [String] {
    var names: [String] = []
    var inString = false
    var escaping = false
    var index = argumentLiteral.startIndex
    var nestingDepth = 0
    let targetDepth = graphQLTopLevelArgumentDepth(in: argumentLiteral)

    while index < argumentLiteral.endIndex {
        let character = argumentLiteral[index]
        if inString {
            if escaping {
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "\"" {
                inString = false
            }
            index = argumentLiteral.index(after: index)
            continue
        }

        if character == "\"" {
            inString = true
            index = argumentLiteral.index(after: index)
            continue
        }
        if let nextIndex = indexAfterGraphQLComment(in: argumentLiteral, from: index) {
            index = nextIndex
            continue
        }
        if character == "(" || character == "[" || character == "{" {
            nestingDepth += 1
            index = argumentLiteral.index(after: index)
            continue
        }
        if character == ")" || character == "]" || character == "}" {
            nestingDepth = max(0, nestingDepth - 1)
            index = argumentLiteral.index(after: index)
            continue
        }

        guard nestingDepth == targetDepth,
              isGraphQLNameStart(character) else {
            index = argumentLiteral.index(after: index)
            continue
        }

        let start = index
        index = argumentLiteral.index(after: index)
        while index < argumentLiteral.endIndex,
              isGraphQLIdentifierCharacter(argumentLiteral[index]) {
            index = argumentLiteral.index(after: index)
        }
        let name = String(argumentLiteral[start..<index])
        let afterName = skipGraphQLIgnored(in: argumentLiteral, from: index)
        if afterName < argumentLiteral.endIndex,
           argumentLiteral[afterName] == ":" {
            names.append(name)
        }
    }

    return names
}

private func graphQLTopLevelArgumentDepth(in source: String) -> Int {
    let firstToken = skipGraphQLIgnored(in: source, from: source.startIndex)
    if firstToken < source.endIndex,
       source[firstToken] == "(" {
        return 1
    }
    return 0
}

func extractOptionalIntArgument(
    _ name: String,
    from document: String,
    defaultValue: Int,
    minimum: Int,
    maximum: Int,
    fieldName: String
) throws -> Int {
    guard let nameRange = rangeOfGraphQLArgument(name, in: document) else {
        return defaultValue
    }
    var index = skipGraphQLIgnored(in: document, from: nameRange.upperBound)
    let digitStart = index
    while index < document.endIndex,
          document[index] >= "0",
          document[index] <= "9" {
        index = document.index(after: index)
    }
    let digits = document[digitStart..<index]
    guard digitStart < index,
          isGraphQLValueTerminated(in: document, at: index),
          let parsed = Int(digits),
          parsed >= minimum,
          parsed <= maximum else {
        throw validation("\(fieldName).\(name) must be an integer between \(minimum) and \(maximum).")
    }
    return parsed
}

func extractRequiredIntArgument(
    _ name: String,
    from document: String,
    minimum: Int,
    maximum: Int,
    fieldName: String
) throws -> Int {
    guard rangeOfGraphQLArgument(name, in: document) != nil else {
        throw validation("\(fieldName) requires \(name).")
    }
    return try extractOptionalIntArgument(
        name,
        from: document,
        defaultValue: minimum,
        minimum: minimum,
        maximum: maximum,
        fieldName: fieldName
    )
}

func extractOptionalBoolArgument(
    _ name: String,
    from document: String,
    defaultValue: Bool,
    fieldName: String
) throws -> Bool {
    guard let nameRange = rangeOfGraphQLArgument(name, in: document) else {
        return defaultValue
    }
    let index = skipGraphQLIgnored(in: document, from: nameRange.upperBound)
    guard index < document.endIndex else {
        throw validation("\(fieldName).\(name) must be a boolean literal.")
    }
    if document[index...].hasPrefix("true"),
       isGraphQLValueTerminated(in: document, at: document.index(index, offsetBy: 4)) {
        return true
    }
    if document[index...].hasPrefix("false"),
       isGraphQLValueTerminated(in: document, at: document.index(index, offsetBy: 5)) {
        return false
    }
    throw validation("\(fieldName).\(name) must be a boolean literal.")
}

func extractOptionalStringArgument(_ name: String, from document: String, fieldName: String) throws -> String? {
    guard let nameRange = rangeOfGraphQLArgument(name, in: document) else {
        return nil
    }
    let index = skipGraphQLIgnored(in: document, from: nameRange.upperBound)
    guard index < document.endIndex,
          document[index] == "\"" else {
        throw validation("\(fieldName).\(name) must be a string literal.")
    }
    let parsed = try parseStringLiteral(from: document, at: index, context: "\(fieldName).\(name)")
    guard isGraphQLValueTerminated(in: document, at: parsed.nextIndex) else {
        throw validation("\(fieldName).\(name) must be a string literal.")
    }
    return nonBlank(parsed.value)
}

func extractStringArgument(_ name: String, from document: String, fieldName: String) throws -> String {
    guard let nameRange = rangeOfGraphQLArgument(name, in: document) else {
        throw validation("\(fieldName) requires \(name).")
    }
    let startQuote = skipGraphQLIgnored(in: document, from: nameRange.upperBound)
    guard startQuote < document.endIndex,
          document[startQuote] == "\"" else {
        throw validation("\(fieldName).\(name) must be a string literal.")
    }

    let parsed = try parseStringLiteral(from: document, at: startQuote, context: "\(fieldName).\(name)")
    if parsed.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw validation("\(fieldName).\(name) must not be empty.")
    }
    guard isGraphQLValueTerminated(in: document, at: parsed.nextIndex) else {
        throw validation("\(fieldName).\(name) must be a string literal.")
    }
    return parsed.value
}

func extractStringArrayArgument(
    _ name: String,
    from document: String,
    fieldName: String,
    minimum: Int = 1,
    maximum: Int
) throws -> [String] {
    guard let values = try extractOptionalStringArrayArgument(
        name,
        from: document,
        fieldName: fieldName,
        minimum: minimum,
        maximum: maximum
    ) else {
        throw validation("\(fieldName) requires \(name).")
    }
    return values
}

func extractOptionalStringArrayArgument(
    _ name: String,
    from document: String,
    fieldName: String,
    minimum: Int = 1,
    maximum: Int
) throws -> [String]? {
    guard let nameRange = rangeOfGraphQLArgument(name, in: document) else {
        return nil
    }
    var index = skipGraphQLIgnored(in: document, from: nameRange.upperBound)
    guard index < document.endIndex,
          document[index] == "[" else {
        throw validation("\(fieldName).\(name) must be a list of string literals.")
    }
    index = document.index(after: index)
    var values: [String] = []
    while true {
        index = skipGraphQLIgnored(in: document, from: index)
        guard index < document.endIndex else {
            throw validation("\(fieldName).\(name) must close with ].")
        }
        if document[index] == "]" {
            index = document.index(after: index)
            break
        }
        guard document[index] == "\"" else {
            throw validation("\(fieldName).\(name) must contain only string literals.")
        }
        let parsed = try parseStringLiteral(from: document, at: index, context: "\(fieldName).\(name)")
        let value = parsed.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            throw validation("\(fieldName).\(name) must not contain empty strings.")
        }
        values.append(value)
        index = skipGraphQLIgnored(in: document, from: parsed.nextIndex)
        if index < document.endIndex,
           document[index] == "," {
            index = document.index(after: index)
            continue
        }
        if index < document.endIndex,
           document[index] == "]" {
            continue
        }
        throw validation("\(fieldName).\(name) entries must be separated by commas.")
    }
    guard isGraphQLValueTerminated(in: document, at: index) else {
        throw validation("\(fieldName).\(name) must be a list of string literals.")
    }
    guard values.count >= minimum,
          values.count <= maximum else {
        throw validation("\(fieldName).\(name) must contain between \(minimum) and \(maximum) values.")
    }
    return values
}
