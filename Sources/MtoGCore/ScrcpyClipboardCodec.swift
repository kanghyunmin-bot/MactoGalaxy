import Foundation

/// Wire contract pinned to scrcpy v3.3.4. No key injection messages are exposed.
public enum ScrcpyClipboardCodec {
    public static let maximumTextBytes = (1 << 18) - 14
    public static let getClipboard = Data([8, 0]) // COPY_KEY_NONE
    public static func setClipboard(_ text: String, sequence: UInt64) throws -> Data {
        let bytes = Data(text.utf8)
        guard bytes.count <= maximumTextBytes else { throw ClipboardEventError.contentTooLarge }
        var result = Data([9])
        for shift in stride(from: 56, through: 0, by: -8) { result.append(UInt8(truncatingIfNeeded: sequence >> shift)) }
        result.append(0) // paste=false, never inject PASTE
        for shift in stride(from: 24, through: 0, by: -8) { result.append(UInt8(truncatingIfNeeded: bytes.count >> shift)) }
        result.append(bytes)
        return result
    }
}

public enum ScrcpyDeviceMessage: Equatable, Sendable {
    case clipboard(String)
    case acknowledgement(UInt64)
}
public enum ScrcpyProtocolError: Error { case invalidMessage, oversized, invalidUTF8 }
public struct ScrcpyClipboardParser: Sendable {
    private var buffer = Data()
    public init() {}
    public mutating func append(_ data: Data) throws -> [ScrcpyDeviceMessage] {
        var result: [ScrcpyDeviceMessage] = []
        // Incrementally inspect length before buffering payload, including concatenated messages.
        for byte in data {
            buffer.append(byte)
            guard let type = buffer.first, type <= 1 else { throw ScrcpyProtocolError.invalidMessage }
            if type == 1 && buffer.count == 9 {
                let sequence = buffer.dropFirst().reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                result.append(.acknowledgement(sequence)); buffer.removeAll(keepingCapacity: true)
            } else if type == 0 && buffer.count >= 5 {
                let length = buffer.dropFirst().prefix(4).reduce(0) { ($0 << 8) | Int($1) }
                // Reject the server truncation boundary instead of importing silently truncated text.
                guard length <= ScrcpyClipboardCodec.maximumTextBytes else { throw ScrcpyProtocolError.oversized }
                if buffer.count == length + 5 {
                    guard let text = String(data: buffer.dropFirst(5), encoding: .utf8) else { throw ScrcpyProtocolError.invalidUTF8 }
                    result.append(.clipboard(text)); buffer.removeAll(keepingCapacity: true)
                }
            }
        }
        return result
    }
}
