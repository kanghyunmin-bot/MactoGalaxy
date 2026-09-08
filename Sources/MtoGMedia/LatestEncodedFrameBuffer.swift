public struct LatestEncodedFrameBuffer {
    public private(set) var droppedFrames = 0
    public private(set) var needsKeyframe = true
    private var pending: RealtimeEncodedFrame?
    private var emittedConfig = false

    public init() {}
    public var isEmpty: Bool { pending == nil }

    public mutating func offer(_ frame: RealtimeEncodedFrame) {
        if frame.accessUnit.isKeyframe {
            if pending != nil { droppedFrames += 1 }
            // Preserve a not-yet-emitted configuration when replacing its keyframe.
            pending = RealtimeEncodedFrame(config: frame.config ?? pending?.config, accessUnit: frame.accessUnit)
            needsKeyframe = false
            return
        }
        guard !needsKeyframe else { droppedFrames += 1; return }
        guard pending == nil else {
            // A compressed delta cannot be replaced as if it were a raw capture.
            // Retain any pending earlier frame, but reject all following deltas until a new keyframe.
            droppedFrames += 1
            needsKeyframe = true
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
