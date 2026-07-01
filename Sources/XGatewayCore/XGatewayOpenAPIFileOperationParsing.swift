import Foundation

let openAPIFileDownloadFields = openAPIFileDownloadDefinitions.map(\.fieldName)
let openAPIFileUploadFields = openAPIFileUploadDefinitions.map(\.fieldName)

struct OpenAPIFileDownloadRequest {
    let fieldName: String
    let path: String
    let outputPath: String
}

struct OpenAPIFileUploadRequest {
    let fieldName: String
    let path: String
    let fields: [(String, String)]
    let fileFieldName: String
    let filePath: String
    let mimeType: String
}

private struct OpenAPIFileDownloadDefinition {
    let fieldName: String
    let pathTemplate: String
    let pathParameters: [String]
}

private struct OpenAPIFileUploadDefinition {
    let fieldName: String
    let pathTemplate: String
    let pathParameters: [String]
    let fieldParameters: [OpenAPIFileFieldParameter]
    let fileArgumentName: String
}

private struct OpenAPIFileFieldParameter {
    let graphQLName: String
    let upstreamName: String
    let required: Bool
    let kind: OpenAPIFileFieldKind
}

private enum OpenAPIFileFieldKind {
    case string
    case stringArray
    case int
    case bool
}

private let openAPIFileDownloadDefinitions = [
    OpenAPIFileDownloadDefinition(
        fieldName: "downloadChatMedia",
        pathTemplate: "/2/chat/media/{id}/{mediaHashKey}",
        pathParameters: ["id", "mediaHashKey"]
    ),
    OpenAPIFileDownloadDefinition(
        fieldName: "downloadDirectMessageMedia",
        pathTemplate: "/2/dm_conversations/media/{dmId}/{mediaId}/{resourceId}",
        pathParameters: ["dmId", "mediaId", "resourceId"]
    )
]

private let openAPIFileUploadDefinitions = [
    OpenAPIFileUploadDefinition(
        fieldName: "uploadMedia",
        pathTemplate: "/2/media/upload",
        pathParameters: [],
        fieldParameters: [
            stringFileField("mediaCategory", upstream: "media_category", required: true),
            stringFileField("mediaType", upstream: "media_type"),
            boolFileField("shared"),
            stringArrayFileField("additionalOwners", upstream: "additional_owners")
        ],
        fileArgumentName: "filePath"
    ),
    OpenAPIFileUploadDefinition(
        fieldName: "appendMediaUpload",
        pathTemplate: "/2/media/upload/{mediaId}/append",
        pathParameters: ["mediaId"],
        fieldParameters: [
            intFileField("segmentIndex", upstream: "segment_index", required: true)
        ],
        fileArgumentName: "filePath"
    ),
    OpenAPIFileUploadDefinition(
        fieldName: "appendChatMediaUpload",
        pathTemplate: "/2/chat/media/upload/{id}/append",
        pathParameters: ["id"],
        fieldParameters: [
            stringFileField("conversationId", upstream: "conversation_id", required: true),
            stringFileField("mediaHashKey", upstream: "media_hash_key", required: true),
            intFileField("segmentIndex", upstream: "segment_index", required: true)
        ],
        fileArgumentName: "filePath"
    )
]

func parseOpenAPIFileDownloadOperation(fieldName: String?, arguments: String) throws -> SupportedGraphQLOperation? {
    guard let definition = openAPIFileDownloadDefinitions.first(where: { $0.fieldName == fieldName }) else {
        return nil
    }
    let allowed = Set(definition.pathParameters + ["outputPath"])
    try validateGraphQLArguments(in: arguments, allowed: allowed, fieldName: definition.fieldName)
    return .openAPIFileDownload(
        OpenAPIFileDownloadRequest(
            fieldName: definition.fieldName,
            path: try resolveFilePathTemplate(definition.pathTemplate, parameters: definition.pathParameters, arguments: arguments, fieldName: definition.fieldName),
            outputPath: try extractStringArgument("outputPath", from: arguments, fieldName: definition.fieldName)
        )
    )
}

func parseOpenAPIFileUploadOperation(fieldName: String?, arguments: String) throws -> SupportedGraphQLOperation? {
    guard let definition = openAPIFileUploadDefinitions.first(where: { $0.fieldName == fieldName }) else {
        return nil
    }
    let allowed = Set(
        definition.pathParameters
            + definition.fieldParameters.map(\.graphQLName)
            + [definition.fileArgumentName]
    )
    try validateGraphQLArguments(in: arguments, allowed: allowed, fieldName: definition.fieldName)
    let filePath = try extractStringArgument(definition.fileArgumentName, from: arguments, fieldName: definition.fieldName)
    return .openAPIFileUpload(
        OpenAPIFileUploadRequest(
            fieldName: definition.fieldName,
            path: try resolveFilePathTemplate(definition.pathTemplate, parameters: definition.pathParameters, arguments: arguments, fieldName: definition.fieldName),
            fields: try extractFileFields(definition.fieldParameters, from: arguments, fieldName: definition.fieldName),
            fileFieldName: "media",
            filePath: filePath,
            mimeType: try extractOptionalStringArgument("mediaType", from: arguments, fieldName: definition.fieldName) ?? inferredOpenAPIMimeType(filePath)
        )
    )
}

private func resolveFilePathTemplate(_ template: String, parameters: [String], arguments: String, fieldName: String) throws -> String {
    var path = template
    for parameter in parameters {
        let value = try extractStringArgument(parameter, from: arguments, fieldName: fieldName)
        path = path.replacingOccurrences(of: "{\(parameter)}", with: urlPathEscape(value))
    }
    return path
}

private func extractFileFields(
    _ parameters: [OpenAPIFileFieldParameter],
    from arguments: String,
    fieldName: String
) throws -> [(String, String)] {
    return try parameters.compactMap { parameter in
        guard let value = try extractFileField(parameter, from: arguments, fieldName: fieldName) else {
            return nil
        }
        return (parameter.upstreamName, value)
    }
}

private func extractFileField(_ parameter: OpenAPIFileFieldParameter, from arguments: String, fieldName: String) throws -> String? {
    switch parameter.kind {
    case .string:
        if parameter.required {
            return try extractStringArgument(parameter.graphQLName, from: arguments, fieldName: fieldName)
        }
        return try extractOptionalStringArgument(parameter.graphQLName, from: arguments, fieldName: fieldName)
    case .stringArray:
        let values = try extractOptionalStringArrayArgument(parameter.graphQLName, from: arguments, fieldName: fieldName, maximum: 100)
        if parameter.required && values == nil {
            throw validation("\(fieldName) requires \(parameter.graphQLName).")
        }
        return values?.joined(separator: ",")
    case .int:
        if parameter.required {
            return String(try extractRequiredIntArgument(parameter.graphQLName, from: arguments, minimum: 0, maximum: Int.max, fieldName: fieldName))
        }
        guard rangeOfGraphQLArgument(parameter.graphQLName, in: arguments) != nil else {
            return nil
        }
        return String(try extractOptionalIntArgument(parameter.graphQLName, from: arguments, defaultValue: 0, minimum: 0, maximum: Int.max, fieldName: fieldName))
    case .bool:
        guard rangeOfGraphQLArgument(parameter.graphQLName, in: arguments) != nil else {
            if parameter.required {
                throw validation("\(fieldName) requires \(parameter.graphQLName).")
            }
            return nil
        }
        return String(try extractOptionalBoolArgument(parameter.graphQLName, from: arguments, defaultValue: false, fieldName: fieldName))
    }
}

private func inferredOpenAPIMimeType(_ filePath: String) -> String {
    switch URL(fileURLWithPath: filePath).pathExtension.lowercased() {
    case "png":
        return "image/png"
    case "jpg", "jpeg", "pjpeg":
        return "image/jpeg"
    case "webp":
        return "image/webp"
    case "bmp":
        return "image/bmp"
    case "tif", "tiff":
        return "image/tiff"
    case "srt":
        return "text/srt"
    case "vtt":
        return "text/vtt"
    default:
        return "application/octet-stream"
    }
}

private func stringFileField(_ graphQLName: String, upstream: String? = nil, required: Bool = false) -> OpenAPIFileFieldParameter {
    return OpenAPIFileFieldParameter(graphQLName: graphQLName, upstreamName: upstream ?? graphQLName, required: required, kind: .string)
}

private func stringArrayFileField(_ graphQLName: String, upstream: String? = nil, required: Bool = false) -> OpenAPIFileFieldParameter {
    return OpenAPIFileFieldParameter(graphQLName: graphQLName, upstreamName: upstream ?? graphQLName, required: required, kind: .stringArray)
}

private func intFileField(_ graphQLName: String, upstream: String? = nil, required: Bool = false) -> OpenAPIFileFieldParameter {
    return OpenAPIFileFieldParameter(graphQLName: graphQLName, upstreamName: upstream ?? graphQLName, required: required, kind: .int)
}

private func boolFileField(_ graphQLName: String, upstream: String? = nil, required: Bool = false) -> OpenAPIFileFieldParameter {
    return OpenAPIFileFieldParameter(graphQLName: graphQLName, upstreamName: upstream ?? graphQLName, required: required, kind: .bool)
}
