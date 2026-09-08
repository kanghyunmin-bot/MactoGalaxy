public enum SessionState: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case reconnecting
    case stoppedByUser
    case failed
}

public enum SessionEvent: Sendable {
    case start
    case connected
    case transportFailed
    case retry
    case userStopped
    case exhausted
}

public struct SessionStateMachine: Sendable {
    public private(set) var state: SessionState = .idle

    public init() {}

    public mutating func handle(_ event: SessionEvent) {
        if state == .stoppedByUser { return }
        switch event {
        case .start:
            state = .connecting
        case .connected:
            state = .connected
        case .transportFailed, .retry:
            state = .reconnecting
        case .userStopped:
            state = .stoppedByUser
        case .exhausted:
            state = .failed
        }
    }
}
