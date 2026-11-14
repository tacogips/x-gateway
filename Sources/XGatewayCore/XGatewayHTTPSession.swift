import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Keep the Linux FoundationNetworking multi-handle alive for the process.
/// Releasing a session after each request can abort in `_MultiHandle.deinit`.
/// Authentication and deadlines belong to each request; this session retains
/// no cookies, URL credentials, or cached response bodies between accounts.
enum XGatewayHTTPSession {
    static let processLifetime: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}
