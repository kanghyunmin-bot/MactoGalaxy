import CryptoKit
import Foundation

public enum AutomaticClipboardKind: String, Codable, Sendable {
    case text
    case url
}

public enum ClipboardEventError: Error, Equatable {
    case emptyContent
    case contentTooLarge
    case invalidIdentity
}

public struct ClipboardEvent: Equatable, Sendable {
    public let sourceID: String
    public let sessionID: String
    public let sequence: UInt64
    public let kind: AutomaticClipboardKind
    public let contentHash: String
    public let content: String

    public init(
        sourceID: String,
        sessionID: String,
        sequence: UInt64,
        kind: AutomaticClipboardKind,
        contentHash: String,
        content: String
    ) {
        self.sourceID = sourceID
        self.sessionID = sessionID
        self.sequence = sequence
        self.kind = kind
        self.contentHash = contentHash
        self.content = content
    }

    public static func make(
        sourceID: String,
        sessionID: String,
        sequence: UInt64,
        kind: AutomaticClipboardKind,
        content: String
    ) throws -> ClipboardEvent {
        guard !sourceID.isEmpty, !sessionID.isEmpty, sequence > 0 else {
            throw ClipboardEventError.invalidIdentity
        }
        guard !content.isEmpty else { throw ClipboardEventError.emptyContent }
        guard content.lengthOfBytes(using: .utf8) <= ProtocolLimits.automaticClipboardBytes else {
            throw ClipboardEventError.contentTooLarge
        }
        return ClipboardEvent(
            sourceID: sourceID,
            sessionID: sessionID,
            sequence: sequence,
            kind: kind,
            contentHash: hash(content),
            content: content
        )
    }

    public static func hash(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
