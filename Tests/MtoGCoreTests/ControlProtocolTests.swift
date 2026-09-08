import Foundation
import Testing
@testable import MtoGCore

struct ControlProtocolTests {
    @Test
    func canonicalFixtureEncodesAndDecodes() throws {
        let fixtureRoot = Self.fixtureRoot
        let semantic = try Data(contentsOf: fixtureRoot.appendingPathComponent("control/hello.json"))
        let expected = try Data(contentsOf: fixtureRoot.appendingPathComponent("control/hello.frame"))
        let envelope = try ControlFrameCodec.decodePayload(semantic)

        #expect(try ControlFrameCodec.encode(envelope) == expected)
        let frames = try BoundedFrameParser().parsing(expected)
        #expect(frames.count == 1)
        #expect(try ControlFrameCodec.decode(frames[0]) == envelope)
    }

    @Test
    func parsesFragmentedAndConsecutiveFrames() throws {
        let bytes = try Data(contentsOf: Self.fixtureRoot.appendingPathComponent("control/hello.frame"))
        let parser = BoundedFrameParser()
        var frames: [ControlFrame] = []
        for byte in bytes + bytes {
            frames += try parser.append(Data([byte]))
        }
        try parser.finish()
        #expect(frames.count == 2)
    }

    @Test(arguments: [1, 4, 11])
    func rejectsTruncatedFrame(prefixLength: Int) throws {
        let bytes = try Data(contentsOf: Self.fixtureRoot.appendingPathComponent("control/hello.frame"))
        let parser = BoundedFrameParser()
        _ = try parser.append(bytes.prefix(prefixLength))
        #expect(throws: ControlProtocolError.self) { try parser.finish() }
    }

    @Test
    func reportsLegacyJSONAsVersionOne() {
        #expect(throws: ControlProtocolError.unsupportedVersion(1)) {
            _ = try BoundedFrameParser().append(Data("{\"legacy\":1}".utf8))
        }
    }

    @Test
    func rejectsInvalidHeadersBeforeBody() throws {
        let valid = try Data(contentsOf: Self.fixtureRoot.appendingPathComponent("control/hello.frame"))
        for (offset, value) in [(0, UInt8(0)), (4, UInt8(1)), (5, UInt8(2)), (6, UInt8(255))] {
            var invalid = valid
            invalid[offset] = value
            #expect(throws: ControlProtocolError.self) {
                _ = try BoundedFrameParser().append(invalid.prefix(ControlFrame.headerBytes))
            }
        }

        var oversized = valid.prefix(ControlFrame.headerBytes)
        oversized.replaceSubrange(8..<12, with: [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(throws: ControlProtocolError.self) {
            _ = try BoundedFrameParser().append(oversized)
        }
    }

    @Test
    func rejectsInvalidUTF8JSONTimestampAndSequence() throws {
        #expect(throws: ControlProtocolError.self) {
            _ = try ControlFrameCodec.decode(ControlFrame(flags: 0, payload: Data([0xFF])))
        }
        #expect(throws: ControlProtocolError.self) {
            _ = try ControlFrameCodec.decode(ControlFrame(flags: 0, payload: Data("{}".utf8)))
        }
        let semantic = try String(
            contentsOf: Self.fixtureRoot.appendingPathComponent("control/hello.json"),
            encoding: .utf8
        )
        let fractional = semantic.replacingOccurrences(
            of: "2026-09-01T00:00:00Z",
            with: "2026-09-01T00:00:00.123Z"
        )
        #expect(try ControlFrameCodec.decodePayload(Data(fractional.utf8)).sequenceNo == 1)
        for invalid in [
            semantic.replacingOccurrences(of: "2026-09-01T00:00:00Z", with: "not-a-time"),
            semantic.replacingOccurrences(of: "\"sequenceNo\": 1", with: "\"sequenceNo\": 0"),
            semantic.replacingOccurrences(of: "00000000-0000-0000-0000-000000000001", with: "not-a-uuid")
        ] {
            #expect(throws: ControlProtocolError.self) {
                _ = try ControlFrameCodec.decodePayload(Data(invalid.utf8))
            }
        }
    }

    private static let fixtureRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/protocol-v2")
}
