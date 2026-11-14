import Foundation

extension XGatewayLiveExecutor {
    func tweetMediaPayload(
        attachments: [PostAttachmentInput]?,
        authorization: XGatewayRequestAuthorization
    ) throws -> [String: Any]? {
        guard let attachments,
              !attachments.isEmpty else {
            return nil
        }

        var mediaIds: [String] = []
        mediaIds.reserveCapacity(attachments.count)
        for attachment in attachments {
            let mediaId = try uploadTweetAttachment(attachment, authorization: authorization)
            if let altText = attachment.altText {
                try createTweetMediaMetadata(mediaId: mediaId, altText: altText, authorization: authorization)
            }
            mediaIds.append(mediaId)
        }
        return ["media_ids": mediaIds]
    }

    private func uploadTweetAttachment(
        _ attachment: PostAttachmentInput,
        authorization: XGatewayRequestAuthorization
    ) throws -> String {
        switch authorization {
        case .bearer:
            return try uploadTweetAttachmentWithOAuth2(attachment, authorization: authorization)
        case .oauth1:
            return try uploadTweetAttachmentWithOAuth1(attachment, authorization: authorization)
        }
    }

    private func uploadTweetAttachmentWithOAuth2(
        _ attachment: PostAttachmentInput,
        authorization: XGatewayRequestAuthorization
    ) throws -> String {
        let media = try readTweetAttachmentData(attachment)
        let mediaType = tweetMimeType(for: attachment.filePath)
        let initPayload = try performJSONRequest(
            method: "POST",
            url: try xUsageAPIURL(path: "/2/media/upload/initialize"),
            authorization: authorization,
            body: [
                "media_type": mediaType,
                "total_bytes": media.count,
                "media_category": tweetOAuth2MediaCategory(for: mediaType)
            ]
        )
        let mediaId = try extractTweetOAuth2MediaId(from: initPayload)
        let chunkSize = 4 * 1_024 * 1_024
        var offset = 0
        var segmentIndex = 0
        while offset < media.count {
            let end = min(offset + chunkSize, media.count)
            let chunk = media.subdata(in: offset..<end)
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
        try ensureTweetOAuth2MediaProcessingComplete(mediaId: mediaId, payload: finalizePayload, authorization: authorization)
        return mediaId
    }

    private func uploadTweetAttachmentWithOAuth1(
        _ attachment: PostAttachmentInput,
        authorization: XGatewayRequestAuthorization
    ) throws -> String {
        let media = try readTweetAttachmentData(attachment)
        let mediaType = tweetMimeType(for: attachment.filePath)
        let uploadURL = try xUploadURL()
        let initPayload = try performFormRequest(
            method: "POST",
            url: uploadURL,
            authorization: authorization,
            parameters: [
                ("command", "INIT"),
                ("total_bytes", String(media.count)),
                ("media_type", mediaType),
                ("media_category", tweetOAuth1MediaCategory(for: mediaType))
            ]
        )
        let mediaId = try extractTweetOAuth1MediaId(from: initPayload)
        let chunkSize = 1_024 * 1_024
        var offset = 0
        var segmentIndex = 0
        while offset < media.count {
            let end = min(offset + chunkSize, media.count)
            let chunk = media.subdata(in: offset..<end)
            _ = try performMultipartRequest(
                method: "POST",
                url: uploadURL,
                authorization: authorization,
                parts: [
                    .field(name: "command", value: "APPEND"),
                    .field(name: "media_id", value: mediaId),
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

        let finalizePayload = try performFormRequest(
            method: "POST",
            url: uploadURL,
            authorization: authorization,
            parameters: [
                ("command", "FINALIZE"),
                ("media_id", mediaId)
            ]
        )
        try ensureTweetOAuth1MediaProcessingComplete(mediaId: mediaId, payload: finalizePayload, authorization: authorization)
        return mediaId
    }

    private func createTweetMediaMetadata(
        mediaId: String,
        altText: String,
        authorization: XGatewayRequestAuthorization
    ) throws {
        switch authorization {
        case .bearer:
            _ = try performJSONRequest(
                method: "POST",
                url: try xUsageAPIURL(path: "/2/media/metadata"),
                authorization: authorization,
                body: [
                    "id": mediaId,
                    "metadata": ["alt_text": ["text": altText]]
                ]
            )
        case .oauth1:
            _ = try performJSONRequest(
                method: "POST",
                url: try xUploadURL(path: "/1.1/media/metadata/create.json"),
                authorization: authorization,
                body: [
                    "media_id": mediaId,
                    "alt_text": ["text": altText]
                ]
            )
        }
    }

    private func ensureTweetOAuth2MediaProcessingComplete(
        mediaId: String,
        payload: Any,
        authorization: XGatewayRequestAuthorization
    ) throws {
        var currentPayload = payload
        for _ in 0..<10 {
            guard let processingInfo = tweetOAuth2ProcessingInfo(from: currentPayload),
                  let state = processingInfo["state"] as? String else {
                return
            }
            if state == "succeeded" {
                return
            }
            if state == "failed" {
                throw tweetMediaProcessingError(mediaId: mediaId, details: jsonString(processingInfo, pretty: false))
            }
            let waitSeconds = max(1, min(mediaProcessingIntValue(processingInfo["check_after_secs"]), 5))
            Thread.sleep(forTimeInterval: TimeInterval(waitSeconds))
            currentPayload = try performJSONRequest(
                method: "GET",
                url: try xUsageAPIURL(path: "/2/media/upload", query: queryItems(["media_id": mediaId])),
                authorization: authorization,
                body: nil
            )
        }
        throw tweetMediaTimeoutError(mediaId: mediaId)
    }

    private func ensureTweetOAuth1MediaProcessingComplete(
        mediaId: String,
        payload: Any,
        authorization: XGatewayRequestAuthorization
    ) throws {
        var currentPayload = payload
        for _ in 0..<10 {
            guard let processingInfo = tweetOAuth1ProcessingInfo(from: currentPayload),
                  let state = processingInfo["state"] as? String else {
                return
            }
            if state == "succeeded" {
                return
            }
            if state == "failed" {
                throw tweetMediaProcessingError(mediaId: mediaId, details: jsonString(processingInfo, pretty: false))
            }
            let waitSeconds = max(1, min(mediaProcessingIntValue(processingInfo["check_after_secs"]), 5))
            Thread.sleep(forTimeInterval: TimeInterval(waitSeconds))
            currentPayload = try performJSONRequest(
                method: "GET",
                url: try xUploadURL(query: queryItems(["command": "STATUS", "media_id": mediaId])),
                authorization: authorization,
                body: nil
            )
        }
        throw tweetMediaTimeoutError(mediaId: mediaId)
    }

    private func tweetMediaProcessingError(mediaId: String, details: String) -> XGatewayErrorPayload {
        XGatewayErrorPayload(
            code: .upstreamFailure,
            summary: "Media processing failed",
            details: details,
            likelyCauses: ["X media processing rejected the uploaded file"],
            remediations: ["Verify the image file format and retry with a supported file."],
            classification: "upstream",
            retryable: false,
            traceId: traceId
        )
    }

    private func tweetMediaTimeoutError(mediaId: String) -> XGatewayErrorPayload {
        XGatewayErrorPayload(
            code: .upstreamFailure,
            summary: "Media processing did not finish",
            details: "The Swift media upload adapter timed out while waiting for media id \(mediaId).",
            likelyCauses: ["X media processing is still pending"],
            remediations: ["Retry the request later.", "Use a smaller supported image file if processing repeatedly times out."],
            classification: "upstream",
            retryable: true,
            traceId: traceId
        )
    }
}

private func readTweetAttachmentData(_ attachment: PostAttachmentInput) throws -> Data {
    let url = try validateAttachmentFileAndReturnURL(attachment)
    do {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
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

private func tweetMimeType(for filePath: String) -> String {
    switch URL(fileURLWithPath: filePath).pathExtension.lowercased() {
    case "png":
        return "image/png"
    case "webp":
        return "image/webp"
    case "gif":
        return "image/gif"
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

private func tweetOAuth1MediaCategory(for mediaType: String) -> String {
    if mediaType == "image/gif" {
        return "TweetGif"
    }
    if mediaType.hasPrefix("video/") {
        return "TweetVideo"
    }
    return "TweetImage"
}

private func tweetOAuth2MediaCategory(for mediaType: String) -> String {
    if mediaType == "image/gif" {
        return "tweet_gif"
    }
    if mediaType.hasPrefix("video/") {
        return "tweet_video"
    }
    return "tweet_image"
}

private func extractTweetOAuth1MediaId(from payload: Any) throws -> String {
    guard let root = payload as? [String: Any] else {
        throw tweetMissingMediaIdError(details: "The Swift media upload adapter expected an object response.")
    }
    if let mediaId = root["media_id_string"] as? String,
       !mediaId.isEmpty {
        return mediaId
    }
    if let mediaId = root["media_id"] {
        return String(describing: mediaId)
    }
    throw tweetMissingMediaIdError(details: "The Swift media upload adapter could not read media_id_string from the upload response.")
}

private func extractTweetOAuth2MediaId(from payload: Any) throws -> String {
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
    throw tweetMissingMediaIdError(details: "The Swift media upload adapter could not read the media id from the upload response.")
}

private func tweetMissingMediaIdError(details: String) -> XGatewayErrorPayload {
    XGatewayErrorPayload(
        code: .upstreamFailure,
        summary: "Media id was missing",
        details: details,
        likelyCauses: ["Unexpected X media upload response shape"],
        remediations: ["Retry and inspect upstream media upload diagnostics if the issue persists."],
        classification: "upstream",
        retryable: false,
        traceId: nil
    )
}

private func tweetOAuth1ProcessingInfo(from payload: Any) -> [String: Any]? {
    guard let root = payload as? [String: Any] else {
        return nil
    }
    return root["processing_info"] as? [String: Any]
}

private func tweetOAuth2ProcessingInfo(from payload: Any) -> [String: Any]? {
    if let data = (payload as? [String: Any])?["data"] as? [String: Any],
       let processingInfo = data["processing_info"] as? [String: Any] {
        return processingInfo
    }
    return (payload as? [String: Any])?["processing_info"] as? [String: Any]
}
