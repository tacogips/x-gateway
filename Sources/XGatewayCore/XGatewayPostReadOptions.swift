public struct XGatewayPostReadOptions: Sendable {
    public let mediaRootDir: String?
    public let downloadMedia: Bool
    public let forceDownload: Bool
    public let includePromoted: Bool

    public init(
        mediaRootDir: String? = nil,
        downloadMedia: Bool = true,
        forceDownload: Bool = false,
        includePromoted: Bool = false
    ) {
        self.mediaRootDir = nonBlank(mediaRootDir)
        self.downloadMedia = downloadMedia
        self.forceDownload = forceDownload
        self.includePromoted = includePromoted
    }

    func withDefaultMediaRootDir(_ defaultMediaRootDir: String?) -> XGatewayPostReadOptions {
        return XGatewayPostReadOptions(
            mediaRootDir: mediaRootDir ?? defaultMediaRootDir,
            downloadMedia: downloadMedia,
            forceDownload: forceDownload,
            includePromoted: includePromoted
        )
    }
}

final class ReplyExpansionRequest {
    let maxResults: Int
    let paginationToken: String?
    let readOptions: XGatewayPostReadOptions
    let child: ReplyExpansionRequest?

    init(
        maxResults: Int,
        paginationToken: String?,
        readOptions: XGatewayPostReadOptions,
        child: ReplyExpansionRequest?
    ) {
        self.maxResults = maxResults
        self.paginationToken = paginationToken
        self.readOptions = readOptions
        self.child = child
    }
}
