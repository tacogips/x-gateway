import Foundation

public enum XGatewayArticleRequestBuilder {
    public static let apiHost = "api.x.com"

    public static func draftBody(title: String, text: String) -> [String: Any] {
        return draftBody(title: title, contentState: plainTextContentState(text: text))
    }

    public static func draftBody(title: String, contentStateJSON: String) throws -> [String: Any] {
        return draftBody(title: title, contentState: try parseContentStateJSON(contentStateJSON))
    }

    private static func draftBody(title: String, contentState: [String: Any]) -> [String: Any] {
        return [
            "title": title,
            "content_state": contentState
        ]
    }

    private static func plainTextContentState(text: String) -> [String: Any] {
        return [
            "blocks": [
                [
                    "key": "xgw0",
                    "text": text,
                    "type": "unstyled",
                    "inline_style_ranges": [],
                    "entity_ranges": [],
                    "data": [:]
                ]
            ],
            "entities": []
        ]
    }

    private static func parseContentStateJSON(_ value: String) throws -> [String: Any] {
        guard let data = value.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw validation("createArticleDraft.contentStateJSON must be a JSON object string.")
        }
        guard let blocks = root["blocks"] as? [[String: Any]],
              !blocks.isEmpty else {
            throw validation("createArticleDraft.contentStateJSON must contain a non-empty blocks array.")
        }
        for (index, block) in blocks.enumerated() {
            guard block["key"] is String,
                  block["text"] is String,
                  block["type"] is String else {
                throw validation("createArticleDraft.contentStateJSON.blocks[\(index)] must include string key, text, and type.")
            }
            guard block["inline_style_ranges"] is [[String: Any]],
                  block["entity_ranges"] is [[String: Any]],
                  block["data"] is [String: Any] else {
                throw validation("createArticleDraft.contentStateJSON.blocks[\(index)] must include inline_style_ranges, entity_ranges, and data.")
            }
        }
        if let entities = root["entities"],
           !(entities is [[String: Any]]) {
            throw validation("createArticleDraft.contentStateJSON.entities must be an array when provided.")
        }
        var contentState = root
        if contentState["entities"] == nil {
            contentState["entities"] = []
        }
        guard JSONSerialization.isValidJSONObject(contentState) else {
            throw validation("createArticleDraft.contentStateJSON must be valid JSON object content.")
        }
        return contentState
    }
}
