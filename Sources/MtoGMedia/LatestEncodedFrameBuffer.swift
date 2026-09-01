public struct LatestEncodedFrameBuffer {
    public private(set) var droppedFrames = 0
    private var pending: RealtimeEncodedFrame?
    private var emittedConfig = false

    public init() {}

    public var isEmpty: Bool { pending == nil }

    public mutating func offer(_ frame: RealtimeEncodedFrame) {
        guard let current = pending else {
            pending = frame
            return
        }
        droppedFrames += 1
        if current.config != nil {
            return
        }
        if frame.config != nil {
            pending = frame
            return
        }
        if current.accessUnit.isKeyframe && !frame.accessUnit.isKeyframe {
            return
        }
        pending = frame
    }

    public mutating func take() -> RealtimeEncodedFrame? {
        guard let pending else { return nil }
        guard emittedConfig || pending.config != nil else { return nil }
        self.pending = nil
        if pending.config != nil { emittedConfig = true }
        return pending
    }
}
