import Foundation

public final class BoundedFrameParser {
    private var buffer = Data()
    private var expectedPayloadBytes: Int?
    private var currentFlags: UInt8 = 0

    public init() {}

    public func append<T: DataProtocol>(_ bytes: T) throws -> [ControlFrame] {
        buffer.append(contentsOf: bytes)
        var frames: [ControlFrame] = []

        while true {
            if expectedPayloadBytes == nil {
                guard buffer.count >= ControlFrame.headerBytes else { break }
                try parseHeader()
                buffer = Data(buffer.dropFirst(ControlFrame.headerBytes))
            }

            guard let expectedPayloadBytes else { break }
            guard buffer.count >= expectedPayloadBytes else { break }
            let payload = Data(buffer.prefix(expectedPayloadBytes))
            buffer = Data(buffer.dropFirst(expectedPayloadBytes))
            frames.append(ControlFrame(flags: currentFlags, payload: payload))
            self.expectedPayloadBytes = nil
        }

        return frames
    }

    public func parsing<T: DataProtocol>(_ bytes: T) throws -> [ControlFrame] {
        let frames = try append(bytes)
        try finish()
        return frames
    }

    public func finish() throws {
        guard buffer.isEmpty, expectedPayloadBytes == nil else {
            throw ControlProtocolError.truncatedFrame
        }
    }

    public func reset() {
        buffer.removeAll(keepingCapacity: false)
        expectedPayloadBytes = nil
        currentFlags = 0
    }

    private func parseHeader() throws {
        if buffer.first == UInt8(ascii: "{") || buffer.first == UInt8(ascii: "[") {
            throw ControlProtocolError.unsupportedVersion(1)
        }
        guard buffer.prefix(4) == ControlFrame.magic else {
            throw ControlProtocolError.invalidMagic
        }
        let version = buffer[4]
        guard version == ProtocolLimits.version else {
            throw ControlProtocolError.unsupportedVersion(version)
        }
        let channel = buffer[5]
        guard channel == ControlFrame.channel else {
            throw ControlProtocolError.invalidChannel(channel)
        }
        let type = buffer[6]
        guard type == ControlFrame.envelopeType else {
            throw ControlProtocolError.invalidType(type)
        }
        currentFlags = buffer[7]
        let declared = UInt64(buffer[8]) << 24
            | UInt64(buffer[9]) << 16
            | UInt64(buffer[10]) << 8
            | UInt64(buffer[11])
        guard declared <= UInt64(ProtocolLimits.controlPayloadBytes) else {
            throw ControlProtocolError.payloadTooLarge(declared)
        }
        expectedPayloadBytes = Int(declared)
    }
}
