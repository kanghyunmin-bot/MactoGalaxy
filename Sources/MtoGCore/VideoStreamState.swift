import Foundation

public enum VideoReceiverAction: Equatable, Sendable {
    case configure(VideoPacket)
    case decode(VideoPacket)
    case requestKeyframe
    case control(VideoPacket)
    case reject
}

public final class VideoReceiverStateMachine {
    private var sessionID: UUID
    private var codec: VideoCodec?
    private var highestSequence: UInt64 = 0
    private var hasConfig = false
    private var needsKeyframe = true

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    public func begin(sessionID: UUID) {
        self.sessionID = sessionID
        highestSequence = 0
        codec = nil
        hasConfig = false
        needsKeyframe = true
    }

    public func reset() {
        highestSequence = 0
        codec = nil
        hasConfig = false
        needsKeyframe = true
    }

    public func markFrameDropped() {
        needsKeyframe = true
    }

    public func receive(_ packet: VideoPacket) -> VideoReceiverAction {
        guard packet.sessionID == sessionID else { return .reject }
        if packet.sequence <= highestSequence { return .reject }

        switch packet.kind {
        case .config:
            codec = packet.codec
            highestSequence = packet.sequence
            hasConfig = true
            needsKeyframe = true
            return .configure(packet)
        case .accessUnit:
            guard hasConfig, packet.codec == codec else {
                highestSequence = packet.sequence
                needsKeyframe = true
                return .requestKeyframe
            }
            highestSequence = packet.sequence
            if needsKeyframe && !packet.isKeyframe { return .requestKeyframe }
            if packet.isKeyframe { needsKeyframe = false }
            return .decode(packet)
        case .control:
            highestSequence = packet.sequence
            return .control(packet)
        }
    }
}

public struct CodecFallbackState: Sendable {
    private var usedFallback = false

    public init() {}

    public mutating func requestFallback(from codec: VideoCodec) -> VideoCodec? {
        guard codec == .hevc, !usedFallback else { return nil }
        usedFallback = true
        return .h264
    }
}
