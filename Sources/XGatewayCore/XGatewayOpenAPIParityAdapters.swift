import Foundation

extension XGatewayLiveExecutor {
    func executeOpenAPIParityOperation(
        operation: SupportedGraphQLOperation,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any]? {
        switch operation {
        case .openAPIQuery(let request), .openAPIMutation(let request):
            let query = request.query.isEmpty ? nil : queryItems(request.query)
            let payload = try performJSONRequest(
                method: request.method,
                url: try xUsageAPIURL(path: request.path, query: query),
                authorization: authorization,
                body: request.body
            )
            return [request.fieldName: XGatewayOpenAPIParityProjector.result(payload)]
        case .openAPIFileUpload(let request):
            let payload = try performOpenAPIFileUpload(request, authorization: authorization)
            return [request.fieldName: XGatewayOpenAPIParityProjector.result(payload)]
        case .openAPIFileDownload(let request):
            let payload = try performOpenAPIFileDownload(request, authorization: authorization)
            return [request.fieldName: XGatewayOpenAPIParityProjector.fileResult(payload)]
        default:
            return nil
        }
    }

    private func performOpenAPIFileUpload(
        _ request: OpenAPIFileUploadRequest,
        authorization: XGatewayRequestAuthorization
    ) throws -> Any {
        let fileData = try readOpenAPIFileData(path: request.filePath, fieldName: request.fieldName)
        let fileName = URL(fileURLWithPath: request.filePath).lastPathComponent
        let parts = request.fields.map { MultipartPart.field(name: $0.0, value: $0.1) }
            + [.file(name: request.fileFieldName, filename: fileName, mimeType: request.mimeType, data: fileData)]
        return try performMultipartRequest(
            method: "POST",
            url: try xUsageAPIURL(path: request.path),
            authorization: authorization,
            parts: parts
        )
    }

    private func performOpenAPIFileDownload(
        _ request: OpenAPIFileDownloadRequest,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        let response = try performBinaryDownloadRequest(
            method: "GET",
            url: try xUsageAPIURL(path: request.path),
            authorization: authorization
        )
        let outputURL = URL(fileURLWithPath: NSString(string: request.outputPath).expandingTildeInPath)
        let directoryURL = outputURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try response.data.write(to: outputURL, options: [.atomic])
        } catch {
            throw validation("\(request.fieldName).outputPath could not be written: \(error.localizedDescription)")
        }
        var result: [String: Any] = [
            "localFilePath": outputURL.path,
            "byteCount": response.data.count
        ]
        if let contentType = response.contentType,
           !contentType.isEmpty {
            result["contentType"] = contentType
        }
        return result
    }
}

enum XGatewayOpenAPIParityProjector {
    static func result(_ payload: Any) -> [String: Any] {
        return [
            "ok": true,
            "payload": payload
        ]
    }

    static func fileResult(_ payload: [String: Any]) -> [String: Any] {
        return [
            "ok": true,
            "payload": payload
        ]
    }
}

private func readOpenAPIFileData(path: String, fieldName: String) throws -> Data {
    let expandedPath = NSString(string: path).expandingTildeInPath
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
        throw validation("\(fieldName).filePath must point to a readable file.")
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath), options: [.mappedIfSafe])
        guard !data.isEmpty else {
            throw validation("\(fieldName).filePath must point to a non-empty file.")
        }
        return data
    } catch let error as XGatewayErrorPayload {
        throw error
    } catch {
        throw validation("\(fieldName).filePath could not be read: \(error.localizedDescription)")
    }
}
