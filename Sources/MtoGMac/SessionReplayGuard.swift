import Foundation

final class SessionReplayGuard {
    private var highestSequenceBySession: [String: UInt64] = [:]

    func reset() {
        highestSequenceBySession.removeAll()
    }

    func accept(_ message: SessionEnvelope) -> Bool {
        let lastSeen = highestSequenceBySession[message.sessionId]
        if let lastSeen, message.sequenceNo <= lastSeen {
            return false
        }

        highestSequenceBySession[message.sessionId] = message.sequenceNo
        return true
    }
}
