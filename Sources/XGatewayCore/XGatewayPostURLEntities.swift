import Foundation

// Provider metadata only: these values never cause URL resolution or network IO.
func postURLEntities(_ tweet: [String: Any]) -> [[String: String]] {
    let note = tweet["note_tweet"] as? [String: Any]
    let origins: [(String, Any?)] = [
        ("entities", tweet["entities"]),
        ("note_tweet.entities", note?["entities"])
    ]
    var result: [[String: String]] = []
    var seen: Set<String> = []
    for (source, value) in origins {
        guard let entities = value as? [String: Any],
              let rows = entities["urls"] as? [Any] else { continue }
        for item in rows {
            guard let row = item as? [String: Any],
                  let url = metadataURL(row["url"]) else { continue }
            var projected = ["url": url, "source": source]
            projected["expandedUrl"] = metadataURL(row["expanded_url"])
            projected["displayUrl"] = boundedMetadataString(row["display_url"], maximum: 2048)
            let identity = [source, url, projected["expandedUrl"] ?? "", projected["displayUrl"] ?? ""].joined(separator: "\0")
            if seen.insert(identity).inserted { result.append(projected) }
        }
    }
    return result
}

private func boundedMetadataString(_ value: Any?, maximum: Int) -> String? {
    guard let text = value as? String, !text.isEmpty, text.utf8.count <= maximum,
          text.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
    return text
}

private func metadataURL(_ value: Any?) -> String? {
    guard let text = boundedMetadataString(value, maximum: 8192),
          text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
          let url = URLComponents(string: text),
          let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
          let host = url.host, !host.isEmpty,
          url.user == nil, url.password == nil else { return nil }
    return text
}
