import Foundation
import MtoGCore
@testable import MtoGMedia
import Testing

struct VideoToolboxRoundTripTests {
    @Test
    func backpressureKeepsConfigWithKeyframe() {
        let keyframe = EncodedAccessUnit(annexBData: Data([1]), presentationTimeUs: 1, isKeyframe: true)
        let delta = EncodedAccessUnit(annexBData: Data([2]), presentationTimeUs: 2, isKeyframe: false)
        var racingBuffer = LatestEncodedFrameBuffer()
        racingBuffer.offer(RealtimeEncodedFrame(config: nil, accessUnit: delta))
        #expect(racingBuffer.take() == nil)
        racingBuffer.offer(RealtimeEncodedFrame(config: Data([7]), accessUnit: keyframe))
        let recovered = racingBuffer.take()
        #expect(recovered?.config == Data([7]))
        #expect(recovered?.accessUnit == keyframe)

        var buffer = LatestEncodedFrameBuffer()
        buffer.offer(RealtimeEncodedFrame(config: Data([9]), accessUnit: keyframe))
        buffer.offer(RealtimeEncodedFrame(config: nil, accessUnit: delta))
        let first = buffer.take()
        #expect(first?.config == Data([9]))
        #expect(first?.accessUnit == keyframe)

        buffer.offer(RealtimeEncodedFrame(config: nil, accessUnit: delta))
        buffer.offer(RealtimeEncodedFrame(config: Data([8]), accessUnit: keyframe))
        let configAfterDelta = buffer.take()
        #expect(configAfterDelta?.config == Data([8]))
        #expect(configAfterDelta?.accessUnit == keyframe)
        buffer.offer(RealtimeEncodedFrame(config: nil, accessUnit: delta))
        buffer.offer(RealtimeEncodedFrame(config: nil, accessUnit: keyframe))
        #expect(buffer.take()?.accessUnit == keyframe)
        buffer.offer(RealtimeEncodedFrame(config: nil, accessUnit: keyframe))
        buffer.offer(RealtimeEncodedFrame(config: nil, accessUnit: delta))
        #expect(buffer.take()?.accessUnit == keyframe)
    }

    @Test
    func bitrateIsResolutionBasedAndCapped() {
        #expect(boundedVideoBitrate(width: 64, height: 48) == 2_000_000)
        #expect(boundedVideoBitrate(width: 8_192, height: 8_192) == 40_000_000)
    }

    @Test
    func hardwareH264RoundTripsThroughProtocol() throws {
        let result = try runRoundTrip(codec: .h264, frameCount: 4)
        #expect(result.decodedFrames == 4)
        #expect(result.width == 64)
        #expect(result.height == 48)
        #expect(result.timestamps == result.timestamps.sorted())
        #expect(result.sawConfig)
        #expect(result.sawKeyframe)
    }

    @Test
    func hevcCapabilityIsExplicit() throws {
        switch VideoToolboxCodecSupport.hardwareStatus(for: .hevc, width: 64, height: 48) {
        case .available:
            let result = try runRoundTrip(codec: .hevc, frameCount: 2)
            #expect(result.decodedFrames == 2)
        case .unavailable(let reason):
            #expect(!reason.isEmpty)
        }
    }

    private func runRoundTrip(codec: VideoCodec, frameCount: Int) throws -> VideoRoundTripResult {
        let source = SyntheticFrameSource(width: 64, height: 48)
        let frames = (0..<frameCount).map { _ in source.next(pattern: .movingSquare) }
        let encoded = try VideoToolboxEncoder(
            codec: codec,
            width: 64,
            height: 48,
            framesPerSecond: 60
        ).encode(frames)
        let sessionID = try #require(UUID(uuidString: "30000000-0000-0000-0000-000000000001"))
        var packets = [VideoPacket(
            kind: .config,
            codec: codec,
            flags: 0,
            sessionID: sessionID,
            sequence: 1,
            presentationTimeUs: 0,
            width: 64,
            height: 48,
            payload: encoded.config
        )]
        packets += encoded.accessUnits.enumerated().map { index, unit in
            VideoPacket(
                kind: .accessUnit,
                codec: codec,
                flags: unit.isKeyframe ? VideoPacket.keyframeFlag : 0,
                sessionID: sessionID,
                sequence: UInt64(index + 2),
                presentationTimeUs: unit.presentationTimeUs,
                width: 64,
                height: 48,
                payload: unit.annexBData
            )
        }

        let parser = BoundedVideoParser()
        var received: [VideoPacket] = []
        for packet in packets {
            let bytes = try VideoPacketCodec.encode(packet)
            for chunk in bytes.chunked(size: 13) {
                received += try parser.append(chunk)
            }
        }
        try parser.finish()
        return try VideoToolboxDecoder(codec: codec).decode(received)
    }
}

private extension Data {
    func chunked(size: Int) -> [Data] {
        stride(from: 0, to: count, by: size).map { offset in
            Data(self[offset..<Swift.min(offset + size, count)])
        }
    }
}
