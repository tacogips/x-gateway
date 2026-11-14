import Foundation

/// A bounded exchange with the embedding runtime's user metadata cache.
/// The SDK owns no files and never stores credentials. Only missing authors
/// are looked up; the caller persists the returned metadata between runs.
final class XGatewayUserMemory {
    private(set) var users: [String: [String: String]] = [:]
    private(set) var added: [String: [String: String]] = [:]
    private(set) var unavailableCount = 0

    static func from(environment: [String: String]) throws -> XGatewayUserMemory? {
        if let countString = environment["X_GW_USER_MEMORY_PARTS"] {
            guard let count = Int(countString), (1...100).contains(count) else {
                throw validation("Invalid X user memory transport parts.")
            }
            let parts = try (0..<count).map { index -> String in
                guard let part = environment["X_GW_USER_MEMORY_JSON_\(index)"], part.utf8.count <= 80_000 else {
                    throw validation("Missing or oversized X user memory transport part.")
                }
                return part
            }
            return try XGatewayUserMemory(json: parts.joined())
        }
        return try environment["X_GW_USER_MEMORY_JSON"].map { try XGatewayUserMemory(json: $0) }
    }

    init(json: String) throws {
        guard json.utf8.count <= 800_000,
              let data = json.data(using: .utf8),
              let rows = try JSONSerialization.jsonObject(with: data) as? [[String: String]],
              rows.count <= 10_000 else {
            throw validation("X user memory must be a bounded array of user metadata.")
        }
        for row in rows {
            guard let user = Self.checked(row), let id = user["id"] else {
                throw validation("X user memory contains invalid user metadata.")
            }
            users[id] = user
        }
    }

    static func checked(_ row: [String: String]) -> [String: String]? {
        guard Set(row.keys).isSubset(of: ["id", "username", "name"]),
              let id = row["id"], id.range(of: #"^[0-9]{1,32}$"#, options: .regularExpression) != nil,
              let username = row["username"], username.range(of: #"^[A-Za-z0-9_]{1,15}$"#, options: .regularExpression) != nil,
              row["name", default: ""].utf8.count <= 512 else { return nil }
        return row
    }

    func read(
        url: URL,
        request: (URL) throws -> Any
    ) throws -> Any {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let expansions = components.queryItems?.first(where: { $0.name == "expansions" })?.value,
              expansions.split(separator: ",").contains(where: { $0 == "author_id" || $0.hasSuffix(".author_id") }) else { return try request(url) }
        // Keep referenced posts and media in the original read, but resolve
        // names separately so known authors are never requested again.
        var retainedFields = expansions.split(separator: ",").filter { $0 != "author_id" && !$0.hasSuffix(".author_id") }.map(String.init)
        for field in expansions.split(separator: ",") where field.hasSuffix(".author_id") {
            let parent = String(field.dropLast(".author_id".count))
            if !retainedFields.contains(parent) { retainedFields.append(parent) }
        }
        let retained = retainedFields.joined(separator: ",")
        let otherUsers = retained.split(separator: ",").contains { $0.contains("mentions") || $0 == "in_reply_to_user_id" }
        components.queryItems = components.queryItems?.filter { $0.name != "expansions" && (otherUsers || $0.name != "user.fields") }
        if !retained.isEmpty { components.queryItems?.append(URLQueryItem(name: "expansions", value: retained)) }
        var fields = components.queryItems?.first(where: { $0.name == "tweet.fields" })?.value?.split(separator: ",").map(String.init) ?? []
        if !fields.contains("author_id") { fields.append("author_id") }
        components.queryItems?.removeAll { $0.name == "tweet.fields" }
        components.queryItems?.append(URLQueryItem(name: "tweet.fields", value: fields.joined(separator: ",")))
        // URLComponents leaves literal '+' in query values. X decodes it as a
        // form-space while OAuth signs the literal plus, invalidating opaque
        // continuation tokens. Reuse the SDK's strict wire encoder.
        var wireValues: [String: String] = [:]
        for item in components.queryItems ?? [] { wireValues[item.name] = item.value ?? "" }
        components.percentEncodedQuery = queryItems(wireValues)
        guard let reducedURL = components.url else { throw validation("Invalid X author-memory request URL.") }
        guard var payload = try request(reducedURL) as? [String: Any] else {
            throw validation("Invalid X post response for author memory.")
        }
        var includes = payload["includes"] as? [String: Any] ?? [:]
        let posts = (payload["data"] as? [[String: Any]] ?? (payload["data"] as? [String: Any]).map { [$0] } ?? [])
            + (includes["tweets"] as? [[String: Any]] ?? [])
        let ids = Set(posts.compactMap { $0["author_id"] as? String })
        guard ids.allSatisfy({ $0.range(of: #"^[0-9]{1,32}$"#, options: .regularExpression) != nil }) else {
            throw validation("Invalid X post author ID.")
        }
        let allMissing = ids.filter { users[$0] == nil }.sorted()
        let usedBytes = try JSONSerialization.data(withJSONObject: Array(users.values)).count
        let capacity = max(0, min(10_000 - users.count, (800_000 - usedBytes) / 768))
        let missing = Array(allMissing.prefix(capacity))
        unavailableCount += allMissing.count - missing.count
        for offset in stride(from: 0, to: missing.count, by: 100) {
            let batch = Array(missing[offset..<min(offset + 100, missing.count)])
            let lookup = try xAPIURL(path: "/2/users", query: queryItems(["ids": batch.joined(separator: ","), "user.fields": "id,name,username"]))
            let response: Any
            do { response = try request(lookup) } catch {
                // Missing optional author metadata must not discard posts.
                // Absence is not remembered as a successful user lookup.
                unavailableCount += batch.count
                continue
            }
            let rows = (response as? [String: Any])?["data"] as? [[String: Any]] ?? []
            for row in rows {
                let strings = row.compactMapValues { $0 as? String }.filter { ["id", "username", "name"].contains($0.key) }
                guard let user = Self.checked(strings), let id = user["id"], batch.contains(id) else { continue }
                users[id] = user
                added[id] = user
            }
            unavailableCount += batch.filter { users[$0] == nil }.count
        }
        var restored = includes["users"] as? [[String: Any]] ?? []
        let present = Set(restored.compactMap { $0["id"] as? String })
        restored += ids.sorted().filter { !present.contains($0) }.compactMap { users[$0] }
        includes["users"] = restored
        payload["includes"] = includes
        return payload
    }

    var delta: [[String: String]] { added.keys.sorted().compactMap { added[$0] } }
}
