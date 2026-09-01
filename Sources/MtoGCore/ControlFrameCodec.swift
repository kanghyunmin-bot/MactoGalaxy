import Foundation

public struct ControlFrame: Equatable, Sendable {
    public static let headerBytes = 12
    public static let magic = Data([0x4D, 0x54, 0x47, 0x32])
    public static let channel: UInt8 = 1
    public static let envelopeType: UInt8 = 1

    public let flags: UInt8
    public let payload: Data

    public init(flags: UInt8, payload: Data) {
        self.flags = flags
        self.payload = payload
    }
}

public enum ControlProtocolError: Error, Equatable {
    case invalidMagic
    case unsupportedVersion(UInt8)
    case invalidChannel(UInt8)
    case invalidType(UInt8)
    case payloadTooLarge(UInt64)
    case truncatedFrame
    case invalidUTF8
    case invalidJSON
}

public enum ControlFrameCodec {
    public static func encode(_ envelope: SessionEnvelope, flags: UInt8 = 0) throws -> Data {
        let payload = try encodePayload(envelope)
        guard payload.count <= ProtocolLimits.controlPayloadBytes else {
            throw ControlProtocolError.payloadTooLarge(UInt64(payload.count))
        }

        var frame = Data(capacity: ControlFrame.headerBytes + payload.count)
        frame.append(ControlFrame.magic)
        frame.append(UInt8(ProtocolLimits.version))
        frame.append(ControlFrame.channel)
        frame.append(ControlFrame.envelopeType)
        frame.append(flags)
        let length = UInt32(payload.count)
        frame.append(UInt8((length >> 24) & 0xFF))
        frame.append(UInt8((length >> 16) & 0xFF))
        frame.append(UInt8((length >> 8) & 0xFF))
        frame.append(UInt8(length & 0xFF))
        frame.append(payload)
        return frame
    }

    public static func encodePayload(_ envelope: SessionEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }

    public static func decode(_ frame: ControlFrame) throws -> SessionEnvelope {
        try decodePayload(frame.payload)
    }

    public static func decodePayload(_ payload: Data) throws -> SessionEnvelope {
        guard String(data: payload, encoding: .utf8) != nil else {
            throw ControlProtocolError.invalidUTF8
        }
        do {
            let envelope = try JSONDecoder().decode(SessionEnvelope.self, from: payload)
            guard envelope.sequenceNo > 0,
                  !envelope.sessionId.isEmpty,
                  !envelope.deviceId.isEmpty,
                  !envelope.deviceName.isEmpty,
                  isValidTimestamp(envelope.sentAt) else {
                throw ControlProtocolError.invalidJSON
            }
            return envelope
        } catch let error as ControlProtocolError {
            throw error
        } catch {
            throw ControlProtocolError.invalidJSON
        }
    }

    private static func isValidTimestamp(_ value: String) -> Bool {
        if ISO8601DateFormatter().date(from: value) != nil {
            return true
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) != nil
    }
}
