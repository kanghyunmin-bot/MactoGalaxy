import Foundation

public enum VideoProtocolError: Error, Equatable {
    case invalidMagic
    case unsupportedVersion(UInt8)
    case invalidKind(UInt8)
    case invalidCodec(UInt8)
    case invalidFlags
    case invalidSession
    case invalidSequence
    case invalidTimestamp
    case invalidDimensions
    case invalidControlCode(UInt8)
    case invalidPayload
    case payloadTooLarge(UInt64)
    case truncatedPacket
}

public enum VideoPacketCodec {
    public static func encode(_ packet: VideoPacket) throws -> Data {
        try validate(packet)
        var data = Data(capacity: VideoPacket.headerBytes + packet.payload.count)
        data.append(VideoPacket.magic)
        data.append(UInt8(ProtocolLimits.version))
        data.append(packet.kind.rawValue)
        data.append(codecByte(packet.codec))
        data.append(packet.flags)
        data.append(contentsOf: uuidBytes(packet.sessionID))
        appendUInt64(packet.sequence, to: &data)
        appendUInt64(packet.presentationTimeUs, to: &data)
        appendUInt32(UInt32(packet.width), to: &data)
        appendUInt32(UInt32(packet.height), to: &data)
        appendUInt32(UInt32(packet.payload.count), to: &data)
        data.append(packet.controlCode.rawValue)
        data.append(Data(repeating: 0, count: 11))
        data.append(packet.payload)
        return data
    }

    public static func decode(_ data: Data) throws -> VideoPacket {
        guard data.count >= VideoPacket.headerBytes else { throw VideoProtocolError.truncatedPacket }
        let length = try declaredPayloadLength(in: data.prefix(VideoPacket.headerBytes))
        guard data.count == VideoPacket.headerBytes + length else { throw VideoProtocolError.truncatedPacket }
        let header = Data(data.prefix(VideoPacket.headerBytes))
        let kind = try kind(header[5])
        let codec = try codec(header[6])
        guard header[7] & ~VideoPacket.keyframeFlag == 0 else { throw VideoProtocolError.invalidFlags }
        let controlCode = VideoControlCode(rawValue: header[52])
        guard let controlCode else { throw VideoProtocolError.invalidControlCode(header[52]) }
        let packet = VideoPacket(
            kind: kind,
            codec: codec,
            flags: header[7],
            sessionID: try uuid(Array(header[8..<24])),
            sequence: readUInt64(header, at: 24),
            presentationTimeUs: readUInt64(header, at: 32),
            width: Int(readUInt32(header, at: 40)),
            height: Int(readUInt32(header, at: 44)),
            controlCode: controlCode,
            payload: Data(data.dropFirst(VideoPacket.headerBytes))
        )
        try validate(packet)
        return packet
    }

    public static func declaredPayloadLength<T: DataProtocol>(in headerBytes: T) throws -> Int {
        let header = Data(headerBytes)
        guard header.count >= VideoPacket.headerBytes else { throw VideoProtocolError.truncatedPacket }
        guard header.prefix(4) == VideoPacket.magic else { throw VideoProtocolError.invalidMagic }
        guard header[4] == ProtocolLimits.version else { throw VideoProtocolError.unsupportedVersion(header[4]) }
        let packetKind = try kind(header[5])
        _ = try codec(header[6])
        guard header[7] & ~VideoPacket.keyframeFlag == 0 else { throw VideoProtocolError.invalidFlags }
        _ = try uuid(Array(header[8..<24]))
        let sequence = readUInt64(header, at: 24)
        guard sequence > 0, sequence <= UInt64(Int64.max) else { throw VideoProtocolError.invalidSequence }
        guard readUInt64(header, at: 32) <= UInt64(Int64.max) else { throw VideoProtocolError.invalidTimestamp }
        let width = Int(readUInt32(header, at: 40))
        let height = Int(readUInt32(header, at: 44))
        guard width > 0, height > 0,
              width <= ProtocolLimits.maximumVideoDimension,
              height <= ProtocolLimits.maximumVideoDimension else { throw VideoProtocolError.invalidDimensions }
        guard let controlCode = VideoControlCode(rawValue: header[52]) else {
            throw VideoProtocolError.invalidControlCode(header[52])
        }
        guard header[53..<64].allSatisfy({ $0 == 0 }) else { throw VideoProtocolError.invalidPayload }
        if packetKind == .control {
            guard controlCode != .none else { throw VideoProtocolError.invalidPayload }
        } else {
            guard controlCode == .none else { throw VideoProtocolError.invalidPayload }
        }
        let declared = UInt64(readUInt32(header, at: 48))
        let limit: Int
        switch packetKind {
        case .config: limit = ProtocolLimits.videoConfigBytes
        case .accessUnit: limit = ProtocolLimits.videoPayloadBytes
        case .control: limit = ProtocolLimits.videoControlBytes
        }
        guard declared > 0 else { throw VideoProtocolError.invalidPayload }
        guard declared <= UInt64(limit) else { throw VideoProtocolError.payloadTooLarge(declared) }
        return Int(declared)
    }

    private static func validate(_ packet: VideoPacket) throws {
        guard packet.flags & ~VideoPacket.keyframeFlag == 0 else { throw VideoProtocolError.invalidFlags }
        guard packet.sessionID != zeroUUID else { throw VideoProtocolError.invalidSession }
        guard packet.sequence > 0, packet.sequence <= UInt64(Int64.max) else { throw VideoProtocolError.invalidSequence }
        guard packet.presentationTimeUs <= UInt64(Int64.max) else { throw VideoProtocolError.invalidTimestamp }
        guard packet.width > 0, packet.height > 0,
              packet.width <= ProtocolLimits.maximumVideoDimension,
              packet.height <= ProtocolLimits.maximumVideoDimension else {
            throw VideoProtocolError.invalidDimensions
        }
        guard !packet.payload.isEmpty else { throw VideoProtocolError.invalidPayload }
        let limit: Int
        switch packet.kind {
        case .config:
            limit = ProtocolLimits.videoConfigBytes
            guard packet.controlCode == .none else { throw VideoProtocolError.invalidPayload }
        case .accessUnit:
            limit = ProtocolLimits.videoPayloadBytes
            guard packet.controlCode == .none else { throw VideoProtocolError.invalidPayload }
        case .control:
            limit = ProtocolLimits.videoControlBytes
            guard packet.controlCode != .none else { throw VideoProtocolError.invalidPayload }
        }
        guard packet.payload.count <= limit else {
            throw VideoProtocolError.payloadTooLarge(UInt64(packet.payload.count))
        }
    }

    private static func kind(_ byte: UInt8) throws -> VideoPacketKind {
        guard let value = VideoPacketKind(rawValue: byte) else { throw VideoProtocolError.invalidKind(byte) }
        return value
    }

    private static func codec(_ byte: UInt8) throws -> VideoCodec {
        switch byte {
        case 1: return .h264
        case 2: return .hevc
        default: throw VideoProtocolError.invalidCodec(byte)
        }
    }

    private static func codecByte(_ codec: VideoCodec) -> UInt8 { codec == .h264 ? 1 : 2 }

    private static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    private static func uuidBytes(_ value: UUID) -> [UInt8] {
        withUnsafeBytes(of: value.uuid) { Array($0) }
    }

    private static func uuid(_ bytes: [UInt8]) throws -> UUID {
        guard bytes.count == 16, bytes.contains(where: { $0 != 0 }) else { throw VideoProtocolError.invalidSession }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xFF)); data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF)); data.append(UInt8(value & 0xFF))
    }

    private static func appendUInt64(_ value: UInt64, to data: inout Data) {
        for shift in stride(from: 56, through: 0, by: -8) { data.append(UInt8((value >> UInt64(shift)) & 0xFF)) }
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        (0..<8).reduce(0) { ($0 << 8) | UInt64(data[offset + $1]) }
    }
}
