import Foundation

func isGraphQLNameStart(_ character: Character) -> Bool {
    return character == "_" || character.isLetter
}

func isGraphQLIdentifierCharacter(_ character: Character) -> Bool {
    return character == "_" || character.isLetter || character.isNumber
}

func isGraphQLWhitespace(_ character: Character) -> Bool {
    return character == " " || character == "\n" || character == "\t" || character == "\r"
}

func hasGraphQLFragmentSpreadBeforeName(in source: String, before nameStart: String.Index) -> Bool {
    var index = nameStart
    while index > source.startIndex {
        let previous = source.index(before: index)
        if !isGraphQLWhitespace(source[previous]) {
            break
        }
        index = previous
    }

    var dotIndex = index
    for _ in 0..<3 {
        guard dotIndex > source.startIndex else {
            return false
        }
        dotIndex = source.index(before: dotIndex)
        guard source[dotIndex] == "." else {
            return false
        }
    }
    return true
}

func parseStringLiteral(
    from source: String,
    at startQuote: String.Index,
    context: String
) throws -> (value: String, nextIndex: String.Index) {
    var value = ""
    var escaping = false
    var index = source.index(after: startQuote)
    while index < source.endIndex {
        let character = source[index]
        if escaping {
            switch character {
            case "\"", "\\":
                value.append(character)
            case "n":
                value.append("\n")
            case "r":
                value.append("\r")
            case "t":
                value.append("\t")
            default:
                value.append(character)
            }
            escaping = false
        } else if character == "\\" {
            escaping = true
        } else if character == "\"" {
            return (value, source.index(after: index))
        } else {
            value.append(character)
        }
        index = source.index(after: index)
    }
    throw validation("\(context) string literal is unterminated.")
}

func extractBalancedLiteral(
    from source: String,
    startingAt startIndex: String.Index,
    opening: Character,
    closing: Character,
    context: String
) throws -> (literal: String, nextIndex: String.Index) {
    var depth = 0
    var inString = false
    var escaping = false
    var index = startIndex

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
        } else if character == "\"" {
            inString = true
        } else if let nextIndex = indexAfterGraphQLComment(in: source, from: index) {
            index = nextIndex
            continue
        } else if character == opening {
            depth += 1
        } else if character == closing {
            depth -= 1
            if depth == 0 {
                let endIndex = source.index(after: index)
                return (String(source[startIndex..<endIndex]), endIndex)
            }
        }
        index = source.index(after: index)
    }

    throw validation("\(context) literal is unterminated.")
}

private func skipWhitespace(in source: String, from startIndex: String.Index) -> String.Index {
    var index = startIndex
    while index < source.endIndex,
          isGraphQLWhitespace(source[index]) {
        index = source.index(after: index)
    }
    return index
}

func skipGraphQLIgnored(in source: String, from startIndex: String.Index) -> String.Index {
    var index = startIndex
    while index < source.endIndex {
        let afterWhitespace = skipWhitespace(in: source, from: index)
        if let afterComment = indexAfterGraphQLComment(in: source, from: afterWhitespace) {
            index = afterComment
            continue
        }
        return afterWhitespace
    }
    return index
}

func indexAfterGraphQLComment(in source: String, from startIndex: String.Index) -> String.Index? {
    guard startIndex < source.endIndex,
          source[startIndex] == "#" else {
        return nil
    }

    var index = source.index(after: startIndex)
    while index < source.endIndex,
          source[index] != "\n",
          source[index] != "\r" {
        index = source.index(after: index)
    }
    return index
}

func isGraphQLValueTerminated(in source: String, at index: String.Index) -> Bool {
    let next = skipGraphQLIgnored(in: source, from: index)
    guard next < source.endIndex else {
        return true
    }
    return source[next] == "," || source[next] == ")" || source[next] == "]" || source[next] == "}"
}

func validateReplyLookupPostId(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw validation("postId must not be empty.")
    }
    if trimmed.contains(where: { $0.isWhitespace }) {
        throw validation("postId must be a single token without whitespace.")
    }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_:-")
    for scalar in trimmed.unicodeScalars where !allowed.contains(scalar) {
        throw validation("postId contains unsupported characters for reply lookup search.")
    }
    return trimmed
}
