public enum VideoCodec: String, Codable, Sendable {
    case hevc
    case h264
}

public struct CodecCapabilities: Equatable, Sendable {
    public let codecs: [VideoCodec]
    public let maxWidth: Int
    public let maxHeight: Int
    public let maxFramesPerSecond: Int

    public init(codecs: [VideoCodec], maxWidth: Int, maxHeight: Int, maxFramesPerSecond: Int) {
        self.codecs = codecs
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.maxFramesPerSecond = maxFramesPerSecond
    }
}

public struct NegotiatedCodec: Equatable, Sendable {
    public let codec: VideoCodec
    public let width: Int
    public let height: Int
    public let framesPerSecond: Int
}

public enum CodecNegotiationError: Error {
    case invalidCapabilities
    case unsupportedCodec
}

public enum CodecNegotiator {
    public static func negotiate(sender: CodecCapabilities, receiver: CodecCapabilities) throws -> NegotiatedCodec {
        guard sender.maxWidth > 0, sender.maxHeight > 0, sender.maxFramesPerSecond > 0,
              receiver.maxWidth > 0, receiver.maxHeight > 0, receiver.maxFramesPerSecond > 0 else {
            throw CodecNegotiationError.invalidCapabilities
        }
        let codec = [VideoCodec.hevc, .h264].first {
            sender.codecs.contains($0) && receiver.codecs.contains($0)
        }
        guard let codec else { throw CodecNegotiationError.unsupportedCodec }
        return NegotiatedCodec(
            codec: codec,
            width: min(sender.maxWidth, receiver.maxWidth),
            height: min(sender.maxHeight, receiver.maxHeight),
            framesPerSecond: min(sender.maxFramesPerSecond, receiver.maxFramesPerSecond)
        )
    }
}
