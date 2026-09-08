import Foundation

public final class BoundedVideoParser {
    private var buffer = Data()
    private var expectedPayloadBytes: Int?

    public init() {}

    public func append<T: DataProtocol>(_ bytes: T) throws -> [VideoPacket] {
        var packets: [VideoPacket] = []
        for region in bytes.regions {
            var index = region.startIndex
            while index != region.endIndex {
                let target = expectedPayloadBytes.map { VideoPacket.headerBytes + $0 } ?? VideoPacket.headerBytes
                let needed = max(target - buffer.count, 1)
                let count = min(needed, region.distance(from: index, to: region.endIndex))
                let next = region.index(index, offsetBy: count)
                buffer.append(contentsOf: region[index..<next])
                index = next
                try drain(into: &packets)
            }
        }
        return packets
    }

    public func parsing<T: DataProtocol>(_ bytes: T) throws -> [VideoPacket] {
        let packets = try append(bytes)
        try finish()
        return packets
    }

    public func finish() throws {
        guard buffer.isEmpty, expectedPayloadBytes == nil else { throw VideoProtocolError.truncatedPacket }
    }

    public func reset() {
        buffer.removeAll(keepingCapacity: false)
        expectedPayloadBytes = nil
    }

    private func drain(into packets: inout [VideoPacket]) throws {
        while true {
            if expectedPayloadBytes == nil {
                guard buffer.count >= VideoPacket.headerBytes else { return }
                expectedPayloadBytes = try VideoPacketCodec.declaredPayloadLength(in: buffer)
            }
            guard let expectedPayloadBytes,
                  buffer.count >= VideoPacket.headerBytes + expectedPayloadBytes else { return }
            packets.append(try VideoPacketCodec.decode(buffer))
            buffer.removeAll(keepingCapacity: true)
            self.expectedPayloadBytes = nil
        }
    }
}
