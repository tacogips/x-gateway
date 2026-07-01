import Foundation

private enum GraphQLInputValue {
    case string(String)
    case null
}

private let supportedPostAttachmentFields: Set<String> = ["kind", "filePath", "altText"]
private let supportedPostAttachmentKinds: Set<String> = ["image", "gif", "video"]
private let imageAttachmentExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]
private let gifAttachmentExtensions: Set<String> = ["gif"]
private let videoAttachmentExtensions: Set<String> = ["mp4", "mov", "webm"]

func extractPostAttachmentsIfPresent(
    from document: String,
    fieldName: String
) throws -> [PostAttachmentInput]? {
    guard let nameRange = rangeOfGraphQLArgument("attachments", in: document) else {
        return nil
    }

    let index = skipGraphQLIgnored(in: document, from: nameRange.upperBound)
    guard index < document.endIndex,
          document[index] == "[" else {
        throw validation("attachments must contain between 1 and 4 items when provided.")
    }

    let extracted = try extractBalancedLiteral(
        from: document,
        startingAt: index,
        opening: "[",
        closing: "]",
        context: "\(fieldName).attachments"
    )
    return try parsePostAttachmentList(extracted.literal, fieldName: fieldName)
}

private func parsePostAttachmentList(_ literal: String, fieldName: String) throws -> [PostAttachmentInput] {
    let inner = String(literal.dropFirst().dropLast())
    var attachments: [PostAttachmentInput] = []
    var index = skipGraphQLIgnored(in: inner, from: inner.startIndex)

    while index < inner.endIndex {
        if inner[index] == "," {
            index = skipGraphQLIgnored(in: inner, from: inner.index(after: index))
            continue
        }

        guard inner[index] == "{" else {
            throw validation("attachments[\(attachments.count)] must be an object with kind, filePath, and optional altText.")
        }

        let extracted = try extractBalancedLiteral(
            from: inner,
            startingAt: index,
            opening: "{",
            closing: "}",
            context: "\(fieldName).attachments[\(attachments.count)]"
        )
        attachments.append(try parsePostAttachmentObject(extracted.literal, index: attachments.count))
        index = skipGraphQLIgnored(in: inner, from: extracted.nextIndex)

        if index < inner.endIndex,
           inner[index] != "," {
            throw validation("attachments[\(attachments.count)] must be separated by commas.")
        }
    }

    guard !attachments.isEmpty,
          attachments.count <= 4 else {
        throw validation("attachments must contain between 1 and 4 items when provided.")
    }
    try validatePostAttachmentComposition(attachments)

    return attachments
}

private func parsePostAttachmentObject(_ literal: String, index attachmentIndex: Int) throws -> PostAttachmentInput {
    let inner = String(literal.dropFirst().dropLast())
    var fields: [String: GraphQLInputValue] = [:]
    var index = skipGraphQLIgnored(in: inner, from: inner.startIndex)

    while index < inner.endIndex {
        if inner[index] == "," {
            index = skipGraphQLIgnored(in: inner, from: inner.index(after: index))
            continue
        }

        let keyStart = index
        while index < inner.endIndex,
              isGraphQLIdentifierCharacter(inner[index]) {
            index = inner.index(after: index)
        }
        guard keyStart < index else {
            throw validation("attachments[\(attachmentIndex)] must be an object with kind, filePath, and optional altText.")
        }
        let key = String(inner[keyStart..<index])
        guard supportedPostAttachmentFields.contains(key) else {
            throw validation("attachments[\(attachmentIndex)] does not accept field '\(key)'. Supported fields: kind, filePath, altText.")
        }

        index = skipGraphQLIgnored(in: inner, from: index)
        guard index < inner.endIndex,
              inner[index] == ":" else {
            throw validation("attachments[\(attachmentIndex)].\(key) requires a value.")
        }
        index = skipGraphQLIgnored(in: inner, from: inner.index(after: index))

        let parsed = try parseGraphQLInputValue(from: inner, at: index, context: "attachments[\(attachmentIndex)].\(key)")
        fields[key] = parsed.value
        index = skipGraphQLIgnored(in: inner, from: parsed.nextIndex)

        if index < inner.endIndex,
           inner[index] != "," {
            throw validation("attachments[\(attachmentIndex)] fields must be separated by commas.")
        }
    }

    guard case .string(let kind)? = fields["kind"],
          supportedPostAttachmentKinds.contains(kind) else {
        throw validation("attachments[\(attachmentIndex)].kind must be one of: image, gif, video.")
    }

    guard case .string(let filePath)? = fields["filePath"],
          !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw validation("attachments[\(attachmentIndex)].filePath must be a non-empty string.")
    }
    try validateAttachmentExtension(kind: kind, filePath: filePath, attachmentIndex: attachmentIndex)

    let altText: String?
    switch fields["altText"] {
    case .none:
        altText = nil
    case .string(let value):
        guard kind != "video" else {
            throw validation("attachments[\(attachmentIndex)].altText is supported only for image or gif attachments.")
        }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.count <= 1_000 else {
            throw validation("attachments[\(attachmentIndex)].altText must be between 1 and 1000 characters when provided.")
        }
        altText = value
    case .null:
        throw validation("attachments[\(attachmentIndex)].altText must be between 1 and 1000 characters when provided.")
    }

    return PostAttachmentInput(kind: kind, filePath: filePath, altText: altText)
}

private func validateAttachmentExtension(kind: String, filePath: String, attachmentIndex: Int) throws {
    let fileExtension = URL(fileURLWithPath: filePath).pathExtension.lowercased()
    guard !fileExtension.isEmpty else {
        throw validation("attachments[\(attachmentIndex)].filePath must include a supported media extension.")
    }
    let supportedExtensions: Set<String>
    switch kind {
    case "image":
        supportedExtensions = imageAttachmentExtensions
    case "gif":
        supportedExtensions = gifAttachmentExtensions
    case "video":
        supportedExtensions = videoAttachmentExtensions
    default:
        supportedExtensions = []
    }
    guard supportedExtensions.contains(fileExtension) else {
        let extensions = supportedExtensions.sorted().joined(separator: ", ")
        throw validation("attachments[\(attachmentIndex)].filePath extension must match kind '\(kind)' (\(extensions)).")
    }
}

private func parseGraphQLInputValue(
    from source: String,
    at startIndex: String.Index,
    context: String
) throws -> (value: GraphQLInputValue, nextIndex: String.Index) {
    guard startIndex < source.endIndex else {
        throw validation("\(context) requires a value.")
    }
    if source[startIndex] == "\"" {
        let parsed = try parseStringLiteral(from: source, at: startIndex, context: context)
        return (.string(parsed.value), parsed.nextIndex)
    }
    if source[startIndex...].hasPrefix("null") {
        return (.null, source.index(startIndex, offsetBy: 4))
    }
    throw validation("\(context) must be a string literal.")
}
