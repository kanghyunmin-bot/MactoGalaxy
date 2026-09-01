import Foundation
import Testing
@testable import MtoGCore

struct VideoProtocolTests {
    @Test(arguments: ["h264-config", "h264-keyframe", "h264-delta"])
    func sharedFixturesRoundTrip(name: String) throws {
        let bytes = try Data(contentsOf: Self.fixtureRoot.appendingPathComponent("video/\(name).packet"))
        let packets = try BoundedVideoParser().parsing(bytes)
        #expect(packets.count == 1)
        #expect(try VideoPacketCodec.encode(packets[0]) == bytes)
    }

    @Test
    func parsesFragmentationAndConsecutivePackets() throws {
        let bytes = try Data(contentsOf: Self.fixtureRoot.appendingPathComponent("video/h264-keyframe.packet"))
        let parser = BoundedVideoParser()
        var packets: [VideoPacket] = []
        for byte in bytes + bytes { packets += try parser.append(Data([byte])) }
        try parser.finish()
        #expect(packets.count == 2)
    }

    @Test
    func rejectsMalformedOversizedAndTruncatedPackets() throws {
        let valid = try Data(contentsOf: Self.fixtureRoot.appendingPathComponent("video/h264-keyframe.packet"))
        for (offset, value) in [(0, UInt8(0)), (4, UInt8(1)), (5, UInt8(255)), (6, UInt8(255))] {
            var invalid = valid
            invalid[offset] = value
            #expect(throws: VideoProtocolError.self) {
                _ = try BoundedVideoParser().append(invalid.prefix(VideoPacket.headerBytes))
            }
        }
        var reserved = valid
        reserved[53] = 1
        #expect(throws: VideoProtocolError.invalidPayload) {
            _ = try BoundedVideoParser().append(reserved.prefix(VideoPacket.headerBytes))
        }
        var signedOverflow = valid
        signedOverflow[24] = 0x80
        #expect(throws: VideoProtocolError.invalidSequence) {
            _ = try BoundedVideoParser().append(signedOverflow.prefix(VideoPacket.headerBytes))
        }
        var oversized = valid.prefix(VideoPacket.headerBytes)
        oversized.replaceSubrange(48..<52, with: [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(throws: VideoProtocolError.self) { _ = try BoundedVideoParser().append(oversized) }
        let truncated = BoundedVideoParser()
        _ = try truncated.append(valid.dropLast())
        #expect(throws: VideoProtocolError.truncatedPacket) { try truncated.finish() }
    }

    @Test
    func enforcesConfigSessionSequenceAndKeyframeRecovery() throws {
        let config = try Self.packet("h264-config")
        let keyframe = try Self.packet("h264-keyframe")
        let delta = try Self.packet("h264-delta")
        let receiver = VideoReceiverStateMachine(sessionID: config.sessionID)
        #expect(receiver.receive(delta) == .requestKeyframe)
        receiver.reset()
        #expect(receiver.receive(config) == .configure(config))
        #expect(receiver.receive(keyframe) == .decode(keyframe))
        #expect(receiver.receive(delta) == .decode(delta))
        #expect(receiver.receive(delta) == .reject)

        var stale = delta
        stale = VideoPacket(
            kind: stale.kind,
            codec: stale.codec,
            flags: stale.flags,
            sessionID: UUID(),
            sequence: stale.sequence + 1,
            presentationTimeUs: stale.presentationTimeUs,
            width: stale.width,
            height: stale.height,
            controlCode: stale.controlCode,
            payload: stale.payload
        )
        #expect(receiver.receive(stale) == .reject)
        let nextSession = UUID()
        receiver.begin(sessionID: nextSession)
        #expect(receiver.receive(config) == .reject)
        receiver.begin(sessionID: config.sessionID)
        _ = receiver.receive(config)
        _ = receiver.receive(keyframe)
        receiver.markFrameDropped()
        #expect(receiver.receive(VideoPacket.copying(delta, sequence: 4)) == .requestKeyframe)
        #expect(receiver.receive(VideoPacket.copying(keyframe, sequence: 5)) == .decode(VideoPacket.copying(keyframe, sequence: 5)))
    }

    @Test
    func validatesControlPacketsDimensionsAndTimestamps() throws {
        let base = try Self.packet("h264-keyframe")
        let control = VideoPacket(
            kind: .control,
            codec: .h264,
            flags: 0,
            sessionID: base.sessionID,
            sequence: 4,
            presentationTimeUs: base.presentationTimeUs,
            width: base.width,
            height: base.height,
            controlCode: .requestKeyframe,
            payload: Data([1])
        )
        #expect(try VideoPacketCodec.decode(VideoPacketCodec.encode(control)) == control)
        let invalidDimension = VideoPacket(
            kind: base.kind, codec: base.codec, flags: base.flags, sessionID: base.sessionID,
            sequence: base.sequence, presentationTimeUs: base.presentationTimeUs,
            width: 0, height: base.height, payload: base.payload
        )
        #expect(throws: VideoProtocolError.invalidDimensions) { _ = try VideoPacketCodec.encode(invalidDimension) }
        let invalidTimestamp = VideoPacket(
            kind: base.kind, codec: base.codec, flags: base.flags, sessionID: base.sessionID,
            sequence: base.sequence, presentationTimeUs: UInt64.max,
            width: base.width, height: base.height, payload: base.payload
        )
        #expect(throws: VideoProtocolError.invalidTimestamp) { _ = try VideoPacketCodec.encode(invalidTimestamp) }
        let invalidFlags = VideoPacket(
            kind: base.kind, codec: base.codec, flags: 0x80, sessionID: base.sessionID,
            sequence: base.sequence, presentationTimeUs: base.presentationTimeUs,
            width: base.width, height: base.height, payload: base.payload
        )
        #expect(throws: VideoProtocolError.invalidFlags) { _ = try VideoPacketCodec.encode(invalidFlags) }
        let zeroSession = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        let invalidSession = VideoPacket(
            kind: base.kind, codec: base.codec, flags: base.flags, sessionID: zeroSession,
            sequence: base.sequence, presentationTimeUs: base.presentationTimeUs,
            width: base.width, height: base.height, payload: base.payload
        )
        #expect(throws: VideoProtocolError.invalidSession) { _ = try VideoPacketCodec.encode(invalidSession) }
    }

    @Test
    func queueAndFallbackStayBounded() throws {
        let delta = try Self.packet("h264-delta")
        let queue = VideoLatestFrameQueue(capacity: 2)
        #expect(queue.append(VideoPacket.copying(delta, sequence: 1)) == nil)
        #expect(queue.append(VideoPacket.copying(delta, sequence: 2)) == nil)
        #expect(queue.append(VideoPacket.copying(delta, sequence: 3))?.sequence == 1)
        #expect(queue.count == 2)
        #expect(queue.needsKeyframeRecovery)
        let keyframe = try Self.packet("h264-keyframe")
        queue.acknowledgeDecoded(keyframe)
        #expect(!queue.needsKeyframeRecovery)
        queue.reset()
        _ = queue.append(VideoPacket.copying(keyframe, sequence: 4))
        _ = queue.append(VideoPacket.copying(delta, sequence: 5))
        #expect(queue.append(VideoPacket.copying(delta, sequence: 6))?.isKeyframe == true)
        #expect(queue.needsKeyframeRecovery)
        queue.acknowledgeDecoded(VideoPacket.copying(keyframe, sequence: 4))
        #expect(queue.needsKeyframeRecovery)
        let foreignKeyframe = VideoPacket(
            kind: keyframe.kind, codec: keyframe.codec, flags: keyframe.flags, sessionID: UUID(),
            sequence: 100, presentationTimeUs: keyframe.presentationTimeUs,
            width: keyframe.width, height: keyframe.height, payload: keyframe.payload
        )
        queue.acknowledgeDecoded(foreignKeyframe)
        #expect(queue.needsKeyframeRecovery)
        queue.reset()
        #expect(!queue.needsKeyframeRecovery)
        _ = queue.append(VideoPacket.copying(keyframe, sequence: 4))
        _ = queue.append(VideoPacket.copying(delta, sequence: 5))
        _ = queue.append(VideoPacket.copying(delta, sequence: 6))
        queue.acknowledgeDecoded(VideoPacket.copying(keyframe, sequence: 7))
        #expect(!queue.needsKeyframeRecovery)

        var fallback = CodecFallbackState()
        #expect(fallback.requestFallback(from: .hevc) == .h264)
        #expect(fallback.requestFallback(from: .hevc) == nil)
    }

    private static func packet(_ name: String) throws -> VideoPacket {
        let data = try Data(contentsOf: fixtureRoot.appendingPathComponent("video/\(name).packet"))
        return try #require(BoundedVideoParser().parsing(data).first)
    }

    private static let fixtureRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/protocol-v2")
}
