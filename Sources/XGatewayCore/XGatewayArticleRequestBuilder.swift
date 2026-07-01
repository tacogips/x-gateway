import Foundation

public enum XGatewayArticleRequestBuilder {
    public static let apiHost = "api.x.com"

    public static func draftBody(title: String, text: String) -> [String: Any] {
        return [
            "title": title,
            "content_state": [
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
        ]
    }
}
