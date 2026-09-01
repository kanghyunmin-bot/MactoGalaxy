import Foundation

public enum ClipboardReceiveResult: Equatable, Sendable {
    case accepted(String)
    case localSource
    case staleSession
    case replayed
    case invalidHash
    case contentTooLarge
    case invalidEvent
    case loop
}

public final class ClipboardSyncEngine {
    public let sourceID: String
    public private(set) var sessionID: String

    private var nextSequence: UInt64 = 0
    private var highestSequenceBySource: [String: UInt64] = [:]
    private var recentHashes: [String] = []
    private let recentHashCapacity: Int

    public init(sourceID: String, sessionID: String, recentHashCapacity: Int = 128) {
        precondition(!sourceID.isEmpty && !sessionID.isEmpty && recentHashCapacity > 0)
        self.sourceID = sourceID
        self.sessionID = sessionID
        self.recentHashCapacity = recentHashCapacity
    }

    public func begin(sessionID: String) {
        precondition(!sessionID.isEmpty)
        self.sessionID = sessionID
        nextSequence = 0
        highestSequenceBySource.removeAll(keepingCapacity: true)
    }

    public func makeLocalEvent(kind: AutomaticClipboardKind, content: String) throws -> ClipboardEvent {
        nextSequence += 1
        let event = try ClipboardEvent.make(
            sourceID: sourceID,
            sessionID: sessionID,
            sequence: nextSequence,
            kind: kind,
            content: content
        )
        remember(hash: event.contentHash)
        return event
    }

    public func receive(_ event: ClipboardEvent) -> ClipboardReceiveResult {
        guard !event.sourceID.isEmpty,
              !event.sessionID.isEmpty,
              event.sequence > 0,
              !event.content.isEmpty else { return .invalidEvent }
        guard event.sourceID != sourceID else { return .localSource }
        guard event.sessionID == sessionID else { return .staleSession }
        if let highest = highestSequenceBySource[event.sourceID], event.sequence <= highest {
            return .replayed
        }
        guard event.content.lengthOfBytes(using: .utf8) <= ProtocolLimits.automaticClipboardBytes else {
            return .contentTooLarge
        }
        guard event.contentHash == ClipboardEvent.hash(event.content) else { return .invalidHash }
        highestSequenceBySource[event.sourceID] = event.sequence
        guard !recentHashes.contains(event.contentHash) else { return .loop }
        remember(hash: event.contentHash)
        return .accepted(event.content)
    }

    private func remember(hash: String) {
        recentHashes.removeAll { $0 == hash }
        recentHashes.append(hash)
        if recentHashes.count > recentHashCapacity {
            recentHashes.removeFirst(recentHashes.count - recentHashCapacity)
        }
    }
}
