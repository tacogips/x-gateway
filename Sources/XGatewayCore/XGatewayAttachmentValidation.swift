import Foundation

private let imageAttachmentMaxBytes = 5_000_000
private let gifAttachmentMaxBytes = 15_000_000
private let videoAttachmentMaxBytes = 512_000_000

func validatePostAttachmentComposition(_ attachments: [PostAttachmentInput]) throws {
    let imageCount = attachments.filter { $0.kind == "image" }.count
    let gifCount = attachments.filter { $0.kind == "gif" }.count
    let videoCount = attachments.filter { $0.kind == "video" }.count

    if gifCount > 0 {
        guard attachments.count == 1,
              gifCount == 1 else {
            throw validation("attachments may include only one gif and cannot mix gif with other media.")
        }
        return
    }
    if videoCount > 0 {
        guard attachments.count == 1,
              videoCount == 1 else {
            throw validation("attachments may include only one video and cannot mix video with other media.")
        }
        return
    }
    guard imageCount == attachments.count,
          imageCount <= 4 else {
        throw validation("attachments may include up to 4 images, 1 gif, or 1 video.")
    }
}

func validateAttachmentFileAndReturnURL(_ attachment: PostAttachmentInput) throws -> URL {
    let expandedPath = NSString(string: attachment.filePath).expandingTildeInPath
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
        throw validation("attachments.filePath must point to a readable media file.")
    }

    let url = URL(fileURLWithPath: expandedPath)
    let byteCount: Int
    do {
        let attributes = try FileManager.default.attributesOfItem(atPath: expandedPath)
        byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
    } catch {
        throw validation("attachments.filePath could not be inspected: \(error.localizedDescription)")
    }
    guard byteCount > 0 else {
        throw validation("attachments.filePath must point to a non-empty media file.")
    }
    try validateAttachmentFileSize(attachment, byteCount: byteCount)
    return url
}

private func validateAttachmentFileSize(_ attachment: PostAttachmentInput, byteCount: Int) throws {
    let maxBytes: Int
    let label: String
    switch attachment.kind {
    case "image":
        maxBytes = imageAttachmentMaxBytes
        label = "5 MB"
    case "gif":
        maxBytes = gifAttachmentMaxBytes
        label = "15 MB"
    case "video":
        maxBytes = videoAttachmentMaxBytes
        label = "512 MB"
    default:
        return
    }
    guard byteCount <= maxBytes else {
        throw validation("attachments.filePath for kind '\(attachment.kind)' must be <= \(label).")
    }
}
