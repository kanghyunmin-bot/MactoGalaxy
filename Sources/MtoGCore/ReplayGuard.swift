public final class SessionReplayGuard {
    private var activeSessionID: String?
    private var activeToken: String?
    private var activeClientNonce: String?
    private var activeServerNonce: String?
    private var activeGeneration: UInt64?
    private var highestSequence: UInt64 = 0

    public init() {}

    public func begin(
        sessionID: String,
        token: String,
        clientNonce: String,
        serverNonce: String,
        generation: UInt64
    ) {
        activeSessionID = sessionID
        activeToken = token
        activeClientNonce = clientNonce
        activeServerNonce = serverNonce
        activeGeneration = generation
        highestSequence = 0
    }

    public func reset() {
        activeSessionID = nil
        activeToken = nil
        activeClientNonce = nil
        activeServerNonce = nil
        activeGeneration = nil
        highestSequence = 0
    }

    public func accept(
        sessionID: String,
        token: String,
        clientNonce: String,
        serverNonce: String,
        sequence: UInt64,
        generation: UInt64
    ) -> Bool {
        guard sessionID == activeSessionID,
              token == activeToken,
              clientNonce == activeClientNonce,
              serverNonce == activeServerNonce,
              generation == activeGeneration,
              sequence > highestSequence else {
            return false
        }
        highestSequence = sequence
        return true
    }
}
