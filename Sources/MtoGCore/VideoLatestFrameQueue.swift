import Foundation

public final class VideoLatestFrameQueue {
    public let capacity: Int
    public private(set) var needsKeyframeRecovery = false
    private var recoverySessionID: UUID?
    private var recoveryAfterSequence: UInt64 = 0
    private var storage: [VideoPacket] = []

    public var count: Int { storage.count }

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    @discardableResult
    public func append(_ packet: VideoPacket) -> VideoPacket? {
        precondition(packet.kind == .accessUnit)
        var dropped: VideoPacket?
        if storage.count == capacity {
            dropped = storage.removeFirst()
            if let dropped {
                needsKeyframeRecovery = true
                if recoverySessionID != dropped.sessionID {
                    recoverySessionID = dropped.sessionID
                    recoveryAfterSequence = dropped.sequence
                } else {
                    recoveryAfterSequence = max(recoveryAfterSequence, dropped.sequence)
                }
            }
        }
        storage.append(packet)
        return dropped
    }

    public func removeFirst() -> VideoPacket? {
        storage.isEmpty ? nil : storage.removeFirst()
    }

    public func acknowledgeDecoded(_ packet: VideoPacket) {
        guard packet.isKeyframe,
              packet.sessionID == recoverySessionID,
              packet.sequence > recoveryAfterSequence else { return }
        needsKeyframeRecovery = false
        recoverySessionID = nil
        recoveryAfterSequence = 0
    }

    public func reset() {
        storage.removeAll(keepingCapacity: true)
        needsKeyframeRecovery = false
        recoverySessionID = nil
        recoveryAfterSequence = 0
    }
}
