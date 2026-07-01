import Foundation

extension XGatewayLiveExecutor {
    func directMessageBody(
        text: String,
        attachments: [PostAttachmentInput]?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any] {
        var body: [String: Any] = ["text": text]
        guard let attachments,
              !attachments.isEmpty else {
            return body
        }
        body["attachments"] = try attachments.map { attachment in
            ["media_id": try uploadDirectMessageAttachment(attachment, authorization: authorization)]
        }
        return body
    }

    private func uploadDirectMessageAttachment(
        _ attachment: PostAttachmentInput,
        authorization: XGatewayRequestAuthorization
    ) throws -> String {
        let fileData = try readDirectMessageAttachmentData(attachment)
        let mediaType = directMessageMimeType(for: attachment.filePath)
        let initializePayload = try performJSONRequest(
            method: "POST",
            url: try xUsageAPIURL(path: "/2/media/upload/initialize"),
            authorization: authorization,
            body: [
                "media_type": mediaType,
                "total_bytes": fileData.count,
                "media_category": directMessageMediaCategory(for: mediaType)
            ]
        )
        let mediaId = try extractDirectMessageMediaId(from: initializePayload)
        let chunkSize = 4 * 1_024 * 1_024
        var offset = 0
        var segmentIndex = 0
        while offset < fileData.count {
            let end = min(offset + chunkSize, fileData.count)
            let chunk = fileData.subdata(in: offset..<end)
            _ = try performMultipartRequest(
                method: "POST",
                url: try xUsageAPIURL(path: "/2/media/upload/\(urlPathEscape(mediaId))/append"),
                authorization: authorization,
                parts: [
                    .field(name: "segment_index", value: String(segmentIndex)),
                    .file(
                        name: "media",
                        filename: URL(fileURLWithPath: attachment.filePath).lastPathComponent,
                        mimeType: mediaType,
                        data: chunk
                    )
                ]
            )
            offset = end
            segmentIndex += 1
        }
        let finalizePayload = try performJSONRequest(
            method: "POST",
            url: try xUsageAPIURL(path: "/2/media/upload/\(urlPathEscape(mediaId))/finalize"),
            authorization: authorization,
            body: nil
        )
        try ensureDirectMessageMediaReady(mediaId: mediaId, payload: finalizePayload, authorization: authorization)
        return mediaId
    }

    private func ensureDirectMessageMediaReady(
        mediaId: String,
        payload: Any,
        authorization: XGatewayRequestAuthorization
    ) throws {
        var currentPayload = payload
        for _ in 0..<10 {
            guard let processingInfo = directMessageProcessingInfo(from: currentPayload),
                  let state = processingInfo["state"] as? String else {
                return
            }
            if state == "succeeded" {
                return
            }
            if state == "failed" {
                throw directMessageMediaError(
                    mediaId: mediaId,
                    summary: "DM attachment processing failed",
                    details: String(describing: processingInfo),
                    retryable: false
                )
            }
            let waitSeconds = processingInfo["check_after_secs"] as? Int ?? 1
            Thread.sleep(forTimeInterval: TimeInterval(max(1, waitSeconds)))
            currentPayload = try performJSONRequest(
                method: "GET",
                url: try xUsageAPIURL(path: "/2/media/upload", query: queryItems(["media_id": mediaId])),
                authorization: authorization,
                body: nil
            )
        }
        throw directMessageMediaError(
            mediaId: mediaId,
            summary: "DM attachment processing did not finish",
            details: "The Swift DM attachment upload adapter timed out while waiting for media id \(mediaId).",
            retryable: true
        )
    }
}

private func readDirectMessageAttachmentData(_ attachment: PostAttachmentInput) throws -> Data {
    let expandedPath = NSString(string: attachment.filePath).expandingTildeInPath
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
        throw validation("attachments.filePath must point to a readable media file.")
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath), options: [.mappedIfSafe])
        guard !data.isEmpty else {
            throw validation("attachments.filePath must point to a non-empty media file.")
        }
        return data
    } catch let error as XGatewayErrorPayload {
        throw error
    } catch {
        throw validation("attachments.filePath could not be read: \(error.localizedDescription)")
    }
}

private func directMessageMimeType(for filePath: String) -> String {
    switch URL(fileURLWithPath: filePath).pathExtension.lowercased() {
    case "gif":
        return "image/gif"
    case "png":
        return "image/png"
    case "webp":
        return "image/webp"
    case "jpg", "jpeg":
        return "image/jpeg"
    case "mp4":
        return "video/mp4"
    case "mov":
        return "video/quicktime"
    case "webm":
        return "video/webm"
    default:
        return "image/jpeg"
    }
}

private func directMessageMediaCategory(for mediaType: String) -> String {
    if mediaType == "image/gif" {
        return "dm_gif"
    }
    if mediaType.hasPrefix("video/") {
        return "dm_video"
    }
    return "dm_image"
}

private func extractDirectMessageMediaId(from payload: Any) throws -> String {
    if let data = (payload as? [String: Any])?["data"] as? [String: Any] {
        if let id = data["id"] as? String,
           !id.isEmpty {
            return id
        }
        if let id = data["media_id"] {
            return String(describing: id)
        }
    }
    if let root = payload as? [String: Any],
       let id = root["media_id"] {
        return String(describing: id)
    }
    throw directMessageMediaError(
        mediaId: nil,
        summary: "DM attachment media id was missing",
        details: "The Swift DM attachment upload adapter could not read the media id from the upload response.",
        retryable: false
    )
}

private func directMessageProcessingInfo(from payload: Any) -> [String: Any]? {
    if let data = (payload as? [String: Any])?["data"] as? [String: Any],
       let processingInfo = data["processing_info"] as? [String: Any] {
        return processingInfo
    }
    return (payload as? [String: Any])?["processing_info"] as? [String: Any]
}

private func directMessageMediaError(
    mediaId: String?,
    summary: String,
    details: String,
    retryable: Bool
) -> XGatewayErrorPayload {
    let mediaDetail = mediaId.map { " Media id: \($0)." } ?? ""
    return XGatewayErrorPayload(
        code: .upstreamFailure,
        summary: summary,
        details: details + mediaDetail,
        likelyCauses: ["Unexpected X media upload response shape", "X media processing rejected the attachment"],
        remediations: ["Retry with a smaller supported media file.", "Inspect upstream media upload diagnostics if the issue persists."],
        classification: "upstream",
        retryable: retryable,
        traceId: nil
    )
}
