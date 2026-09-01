import Foundation

public enum VideoPacketKind: UInt8, Sendable {
    case config = 1
    case accessUnit = 2
    case control = 3
}

public enum VideoControlCode: UInt8, Sendable {
    case none = 0
    case requestKeyframe = 1
    case streamStart = 2
    case streamStop = 3
    case capabilities = 4
    case fallbackH264 = 5
}

public struct VideoPacket: Equatable, Sendable {
    public static let headerBytes = 64
    public static let magic = Data([0x4D, 0x54, 0x47, 0x56])
    public static let keyframeFlag: UInt8 = 1

    public let kind: VideoPacketKind
    public let codec: VideoCodec
    public let flags: UInt8
    public let sessionID: UUID
    public let sequence: UInt64
    public let presentationTimeUs: UInt64
    public let width: Int
    public let height: Int
    public let controlCode: VideoControlCode
    public let payload: Data

    public var isKeyframe: Bool { flags & Self.keyframeFlag != 0 }

    public init(
        kind: VideoPacketKind,
        codec: VideoCodec,
        flags: UInt8,
        sessionID: UUID,
        sequence: UInt64,
        presentationTimeUs: UInt64,
        width: Int,
        height: Int,
        controlCode: VideoControlCode = .none,
        payload: Data
    ) {
        self.kind = kind
        self.codec = codec
        self.flags = flags
        self.sessionID = sessionID
        self.sequence = sequence
        self.presentationTimeUs = presentationTimeUs
        self.width = width
        self.height = height
        self.controlCode = controlCode
        self.payload = payload
    }

    public static func copying(_ packet: VideoPacket, sequence: UInt64) -> VideoPacket {
        VideoPacket(
            kind: packet.kind,
            codec: packet.codec,
            flags: packet.flags,
            sessionID: packet.sessionID,
            sequence: sequence,
            presentationTimeUs: packet.presentationTimeUs,
            width: packet.width,
            height: packet.height,
            controlCode: packet.controlCode,
            payload: packet.payload
        )
    }
}
