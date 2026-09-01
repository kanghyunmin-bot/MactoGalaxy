import Foundation
import MtoGCore
import MtoGMedia
import Testing

struct SyntheticFrameSourceTests {
    @Test
    func patternsAreDeterministicAndFramingHandlesFragmentation() throws {
        let sessionID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000001"))
        for pattern in SyntheticFramePattern.allCases {
            let source = SyntheticFrameSource(width: 32, height: 20)
            let first = source.next(pattern: pattern)
            let second = source.next(pattern: pattern)
            #expect(first.bgraBytes.count == 32 * 20 * 4)
            #expect(first.sequence == 1)
            #expect(second.sequence == 2)
            #expect(second.presentationTimeUs > first.presentationTimeUs)

            let packet = VideoPacket(
                kind: .accessUnit,
                codec: .h264,
                flags: VideoPacket.keyframeFlag,
                sessionID: sessionID,
                sequence: first.sequence,
                presentationTimeUs: first.presentationTimeUs,
                width: first.width,
                height: first.height,
                payload: first.bgraBytes
            )
            let encoded = try VideoPacketCodec.encode(packet)
            let parser = BoundedVideoParser()
            var decoded: [VideoPacket] = []
            for chunk in encoded.chunks(of: 7) {
                decoded += try parser.append(chunk)
            }
            try parser.finish()
            #expect(decoded == [packet])
        }
    }

    @Test
    func movingPatternChangesPixels() {
        let source = SyntheticFrameSource(width: 32, height: 20)
        #expect(source.next(pattern: .movingSquare).bgraBytes != source.next(pattern: .movingSquare).bgraBytes)
    }
}

private extension Data {
    func chunks(of size: Int) -> [Data] {
        stride(from: 0, to: count, by: size).map { offset in
            Data(self[offset..<Swift.min(offset + size, count)])
        }
    }
}
