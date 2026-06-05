import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

struct ClipboardSyncPayload {
    static let protocolVersion = "1"
    static let maxTransferBytes = 24 * 1_024 * 1_024
    static let maxTextBytes = 256 * 1_024

    let kind: ClipboardKind
    let text: String?
    let fileName: String?
    let mimeType: String?
    let binaryData: Data?
    let sizeInBytes: Int

    var previewTitle: String {
        switch kind {
        case .text, .url:
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "빈 클립보드" : String(trimmed.prefix(48))
        case .image, .video, .file:
            return fileName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? fileName!
                : "클립보드 항목"
        }
    }

    var wirePayload: [String: String] {
        var payload: [String: String] = [
            "protocolVersion": Self.protocolVersion,
            "kind": kind.wireName,
            "sizeBytes": String(sizeInBytes),
            "sourceId": Self.localSourceId,
            "itemId": UUID().uuidString,
            "createdAtUnixMs": String(Int64(Date().timeIntervalSince1970 * 1000)),
            "sha256": contentHash
        ]
        if let text, !text.isEmpty {
            payload["text"] = text
            payload["encoding"] = "utf-8"
        }
        if let fileName, !fileName.isEmpty {
            payload["name"] = Self.sanitizedFileName(fileName)
        }
        if let mimeType, !mimeType.isEmpty {
            payload["mimeType"] = mimeType
        }
        if let binaryData, !binaryData.isEmpty {
            payload["dataBase64"] = binaryData.base64EncodedString()
        }
        return payload
    }

    static func fromWirePayload(_ payload: [String: String]) -> ClipboardSyncPayload? {
        guard let kind = ClipboardKind(wireName: payload["kind"]) else { return nil }
        if let version = payload["protocolVersion"], version != protocolVersion {
            return nil
        }

        switch kind {
        case .text, .url:
            let text = payload["text"] ?? ""
            let textSize = text.lengthOfBytes(using: .utf8)
            guard !text.isEmpty, textSize <= maxTextBytes else { return nil }
            return ClipboardSyncPayload(
                kind: kind,
                text: text,
                fileName: nil,
                mimeType: payload["mimeType"],
                binaryData: nil,
                sizeInBytes: textSize
            )
        case .image, .video, .file:
            guard let encoded = payload["dataBase64"],
                  encoded.count <= maxBase64Characters(forBytes: maxTransferBytes),
                  let data = Data(base64Encoded: encoded),
                  !data.isEmpty,
                  data.count <= maxTransferBytes else {
                return nil
            }
            if let expectedHash = payload["sha256"],
               expectedHash != sha256Hex(data) {
                return nil
            }
            return ClipboardSyncPayload(
                kind: kind,
                text: nil,
                fileName: payload["name"].map(sanitizedFileName),
                mimeType: payload["mimeType"],
                binaryData: data,
                sizeInBytes: data.count
            )
        }
    }

    static func isFromLocalSource(_ payload: [String: String]) -> Bool {
        payload["sourceId"] == localSourceId
    }

    private var contentHash: String {
        switch kind {
        case .text, .url:
            return Self.sha256Hex(Data((text ?? "").utf8))
        case .image, .video, .file:
            return Self.sha256Hex(binaryData ?? Data())
        }
    }

    static var localSourceId: String {
        let key = "com.mtog.clipboard.sourceId"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func maxBase64Characters(forBytes bytes: Int) -> Int {
        ((bytes + 2) / 3) * 4 + 128
    }

    static func sanitizedFileName(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let parts = name
            .components(separatedBy: illegal)
            .filter { !$0.isEmpty }
        let joined = parts.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return String((joined.isEmpty ? "clipboard-item" : joined).prefix(96))
    }
}

@MainActor
final class ClipboardSyncController {
    var localTextHandler: ((ClipboardSyncPayload) -> Void)?
    var diagnosticHandler: ((String) -> Void)?

    private let pasteboard = NSPasteboard.general
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let maxTransferBytes = ClipboardSyncPayload.maxTransferBytes
    private let maxTextBytes = ClipboardSyncPayload.maxTextBytes
    private let maxCacheBytes = 160 * 1_024 * 1_024
    private let maxCacheFiles = 80
    private let maxCacheAgeSeconds: TimeInterval = 7 * 24 * 60 * 60
    private var pollTimer: Timer?
    private var lastChangeCount: Int
    private var lastObservedSignature: String?
    private var suppressNextLocalEvent = false

    init() {
        lastChangeCount = pasteboard.changeCount
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let cacheDirectory = baseDirectory
            .appendingPathComponent("MtoG", isDirectory: true)
            .appendingPathComponent("ClipboardCache", isDirectory: true)
        try? fileManager.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        self.cacheDirectory = cacheDirectory
        cleanupCache()
    }

    func start() {
        stop()
        cleanupCache()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollClipboard()
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func currentPayload() -> ClipboardSyncPayload? {
        readClipboardPayload()
    }

    func applyRemotePayload(_ payload: ClipboardSyncPayload) {
        suppressNextLocalEvent = true
        pasteboard.clearContents()

        switch payload.kind {
        case .text, .url:
            pasteboard.setString(payload.text ?? "", forType: .string)
        case .image:
            if let binaryData = payload.binaryData {
                let pasteboardType: NSPasteboard.PasteboardType
                if let mimeType = payload.mimeType,
                   let type = UTType(mimeType: mimeType) {
                    pasteboardType = NSPasteboard.PasteboardType(type.identifier)
                } else {
                    pasteboardType = .png
                }
                pasteboard.setData(binaryData, forType: pasteboardType)
                if let image = NSImage(data: binaryData),
                   let tiffData = image.tiffRepresentation {
                    pasteboard.setData(tiffData, forType: .tiff)
                    pasteboard.writeObjects([image])
                }
            }
        case .video, .file:
            guard let binaryData = payload.binaryData else { break }
            let fileURL = writeCachedFile(
                name: payload.fileName,
                mimeType: payload.mimeType,
                data: binaryData
            )
            pasteboard.writeObjects([fileURL as NSURL])
        }

        lastChangeCount = pasteboard.changeCount
        lastObservedSignature = payload.signature
    }

    func historyItem(
        for payload: ClipboardSyncPayload,
        detail: String,
        timestamp: String,
        sizeLabel: String
    ) -> ClipboardHistoryItem {
        let cachedFileURL = cachePayloadForHistory(payload)
        return ClipboardHistoryItem(
            kind: payload.kind,
            title: String(payload.previewTitle.prefix(96)),
            detail: detail,
            timestamp: timestamp,
            sizeLabel: sizeLabel,
            textValue: payload.kind == .text || payload.kind == .url ? payload.text : nil,
            mimeType: payload.mimeType,
            fileName: payload.fileName,
            cachedFilePath: cachedFileURL?.path
        )
    }

    func recopyHistoryItem(_ item: ClipboardHistoryItem) -> Bool {
        suppressNextLocalEvent = true
        pasteboard.clearContents()

        switch item.kind {
        case .text, .url:
            guard let text = item.textValue, !text.isEmpty else { return false }
            pasteboard.setString(text, forType: .string)
        case .image:
            guard let fileURL = existingCachedFileURL(for: item),
                  let imageData = try? Data(contentsOf: fileURL),
                  !imageData.isEmpty else {
                return false
            }
            let pasteboardType: NSPasteboard.PasteboardType
            if let mimeType = item.mimeType,
               let type = UTType(mimeType: mimeType) {
                pasteboardType = NSPasteboard.PasteboardType(type.identifier)
            } else {
                pasteboardType = .png
            }
            pasteboard.setData(imageData, forType: pasteboardType)
            if let image = NSImage(data: imageData),
               let tiffData = image.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
                pasteboard.writeObjects([image])
            }
        case .video, .file:
            guard let fileURL = existingCachedFileURL(for: item) else { return false }
            pasteboard.writeObjects([fileURL as NSURL])
        }

        lastChangeCount = pasteboard.changeCount
        return true
    }

    func downloadHistoryItem(_ item: ClipboardHistoryItem) -> URL? {
        let downloadsDirectory = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        let directory = downloadsDirectory.appendingPathComponent("MtoG Clipboard", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if item.kind == .text || item.kind == .url {
            guard let text = item.textValue, !text.isEmpty else { return nil }
            let destination = uniqueDestinationURL(
                directory: directory,
                fileName: sanitizedDownloadFileName(item.fileName ?? "clipboard-text.txt")
            )
            do {
                try Data(text.utf8).write(to: destination, options: [.atomic])
                return destination
            } catch {
                return nil
            }
        }

        guard let sourceURL = existingCachedFileURL(for: item) else { return nil }
        let destination = uniqueDestinationURL(
            directory: directory,
            fileName: sanitizedDownloadFileName(item.fileName ?? sourceURL.lastPathComponent)
        )
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private func pollClipboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if suppressNextLocalEvent {
            suppressNextLocalEvent = false
            lastObservedSignature = readClipboardPayload()?.signature
            return
        }

        guard let payload = readClipboardPayload() else {
            lastObservedSignature = nil
            return
        }

        guard payload.signature != lastObservedSignature else {
            return
        }

        lastObservedSignature = payload.signature
        localTextHandler?(payload)
    }

    private func readClipboardPayload() -> ClipboardSyncPayload? {
        if let fileURL = pastedFileURL(),
           let payload = filePayload(for: fileURL) {
            return payload
        }

        if let payload = imagePayloadFromPasteboard() {
            return payload
        }

        guard let rawText = pasteboard.string(forType: .string),
              !rawText.isEmpty else {
            return nil
        }
        guard rawText.lengthOfBytes(using: .utf8) <= maxTextBytes else {
            diagnosticHandler?("Mac clipboard text is too large for MVP sync")
            return nil
        }

        let trimmedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ClipboardSyncPayload(
            kind: isURLText(trimmedText) ? .url : .text,
            text: rawText,
            fileName: nil,
            mimeType: "text/plain",
            binaryData: nil,
            sizeInBytes: rawText.lengthOfBytes(using: .utf8)
        )
    }

    private func pastedFileURL() -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.first
    }

    private func filePayload(for fileURL: URL) -> ClipboardSyncPayload? {
        guard isRegularReadableFile(fileURL) else {
            diagnosticHandler?("Mac 클립보드 파일을 읽을 수 없습니다")
            return nil
        }
        guard let fileData = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
              !fileData.isEmpty else {
            diagnosticHandler?("Mac 클립보드 파일을 열지 못했습니다")
            return nil
        }
        guard fileData.count <= maxTransferBytes else {
            diagnosticHandler?("클립보드 항목이 24MB를 초과합니다. 대용량 전송 방식이 필요합니다")
            return nil
        }

        let fileName = ClipboardSyncPayload.sanitizedFileName(fileURL.lastPathComponent)
        let type = UTType(filenameExtension: fileURL.pathExtension)
        let kind: ClipboardKind
        if type?.conforms(to: .image) == true {
            kind = .image
        } else if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true {
            kind = .video
        } else {
            kind = .file
        }

        return ClipboardSyncPayload(
            kind: kind,
            text: nil,
            fileName: fileName,
            mimeType: type?.preferredMIMEType ?? "application/octet-stream",
            binaryData: kind == .image ? normalizedPNGData(from: fileData, fileURL: fileURL) ?? fileData : fileData,
            sizeInBytes: fileData.count
        )
    }

    private func imagePayloadFromPasteboard() -> ClipboardSyncPayload? {
        guard let pngData = pngDataFromPasteboard(),
              !pngData.isEmpty else {
            return nil
        }
        guard pngData.count <= maxTransferBytes else {
            diagnosticHandler?("클립보드 이미지가 24MB를 초과합니다. 대용량 전송 방식이 필요합니다")
            return nil
        }

        return ClipboardSyncPayload(
            kind: .image,
            text: nil,
            fileName: "clipboard-image.png",
            mimeType: "image/png",
            binaryData: pngData,
            sizeInBytes: pngData.count
        )
    }

    private func pngDataFromPasteboard() -> Data? {
        if let pngData = pasteboard.data(forType: .png) {
            return pngData
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData),
           let normalized = normalizedPNGData(from: image) {
            return normalized
        }

        let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]
        if let image = images?.first {
            return normalizedPNGData(from: image)
        }

        return nil
    }

    private func normalizedPNGData(from data: Data, fileURL: URL) -> Data? {
        if fileURL.pathExtension.lowercased() == "png" {
            return data
        }
        guard let image = NSImage(data: data) else { return nil }
        return normalizedPNGData(from: image)
    }

    private func normalizedPNGData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func writeCachedFile(name: String?, mimeType: String?, data: Data) -> URL {
        let fileName = sanitizedFileName(name, mimeType: mimeType)
        let url = cacheDirectory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
        try? data.write(to: url, options: [.atomic])
        cleanupCache()
        return url
    }

    private func cachePayloadForHistory(_ payload: ClipboardSyncPayload) -> URL? {
        guard let binaryData = payload.binaryData, !binaryData.isEmpty else {
            return nil
        }
        return writeCachedFile(
            name: payload.fileName,
            mimeType: payload.mimeType,
            data: binaryData
        )
    }

    private func existingCachedFileURL(for item: ClipboardHistoryItem) -> URL? {
        guard let path = item.cachedFilePath,
              fileManager.fileExists(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func sanitizedDownloadFileName(_ name: String) -> String {
        ClipboardSyncPayload.sanitizedFileName(name)
    }

    private func uniqueDestinationURL(directory: URL, fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = directory.appendingPathComponent(nextName)
            index += 1
        }
        return candidate
    }

    private func sanitizedFileName(_ name: String?, mimeType: String?) -> String {
        let candidate = (name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? name!
            : defaultFileName(for: mimeType)
        return ClipboardSyncPayload.sanitizedFileName(candidate)
    }

    private func defaultFileName(for mimeType: String?) -> String {
        guard let mimeType,
              let type = UTType(mimeType: mimeType) else {
            return "clipboard-item.bin"
        }

        if type.conforms(to: .image) {
            return "clipboard-image.\(type.preferredFilenameExtension ?? "png")"
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            return "clipboard-video.\(type.preferredFilenameExtension ?? "mp4")"
        }
        return "clipboard-file.\(type.preferredFilenameExtension ?? "bin")"
    }

    private func isRegularReadableFile(_ url: URL) -> Bool {
        guard url.isFileURL,
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            return false
        }
        return fileManager.isReadableFile(atPath: url.path)
    }

    private func isURLText(_ text: String) -> Bool {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased() else {
            return false
        }
        return (scheme == "http" || scheme == "https") && components.host?.isEmpty == false
    }

    private func cleanupCache() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let now = Date()
        let entries = urls.compactMap { url -> (url: URL, modified: Date, size: Int) in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return (
                url,
                values?.contentModificationDate ?? .distantPast,
                values?.fileSize ?? 0
            )
        }
        for entry in entries where now.timeIntervalSince(entry.modified) > maxCacheAgeSeconds {
            try? fileManager.removeItem(at: entry.url)
        }

        let remaining = entries
            .filter { fileManager.fileExists(atPath: $0.url.path) }
            .sorted { $0.modified > $1.modified }
        var totalBytes = 0
        for (index, entry) in remaining.enumerated() {
            totalBytes += entry.size
            if index >= maxCacheFiles || totalBytes > maxCacheBytes {
                try? fileManager.removeItem(at: entry.url)
            }
        }
    }
}

private extension ClipboardSyncPayload {
    var signature: String {
        switch kind {
        case .text, .url:
            return "\(kind.wireName)|\(ClipboardSyncPayload.sha256Hex(Data((text ?? "").utf8)))"
        case .image, .video, .file:
            let preview = ClipboardSyncPayload.sha256Hex(binaryData ?? Data())
            return [
                kind.wireName,
                fileName ?? "",
                mimeType ?? "",
                String(sizeInBytes),
                preview
            ].joined(separator: "|")
        }
    }
}

private extension ClipboardKind {
    var wireName: String {
        switch self {
        case .text: return "text"
        case .url: return "url"
        case .image: return "image"
        case .video: return "video"
        case .file: return "file"
        }
    }

    init?(wireName: String?) {
        switch wireName?.lowercased() {
        case "text": self = .text
        case "url": self = .url
        case "image": self = .image
        case "video": self = .video
        case "file": self = .file
        default: return nil
        }
    }
}
