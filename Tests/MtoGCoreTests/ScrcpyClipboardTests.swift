import Foundation
import Testing
@testable import MtoGCore

struct ScrcpyClipboardTests {
    @Test func wireAndFragmentation() throws {
        let text = "한글😀https://example.com"
        let packet = try ScrcpyClipboardCodec.setClipboard(text, sequence: 42)
        #expect(Array(packet.prefix(10)) == [9,0,0,0,0,0,0,0,42,0])
        #expect(ScrcpyClipboardCodec.getClipboard == Data([8,0]))
        var parser = ScrcpyClipboardParser()
        let device = Data([0]) + packet.dropFirst(10) + Data([1,0,0,0,0,0,0,0,42])
        var received: [ScrcpyDeviceMessage] = []
        for byte in device { received += try parser.append(Data([byte])) }
        #expect(received == [.clipboard(text), .acknowledgement(42)])
    }
    @Test func invalidAndLimits() throws {
        #expect(throws: ClipboardEventError.contentTooLarge) {
            _ = try ScrcpyClipboardCodec.setClipboard(String(repeating: "a", count: 262131), sequence: 1)
        }
        #expect(try ScrcpyClipboardCodec.setClipboard(String(repeating: "a", count: 262130), sequence: 1).count == 262144)
        var parser = ScrcpyClipboardParser()
        #expect(throws: ScrcpyProtocolError.self) { _ = try parser.append(Data([0,0,4,0,0])) }
        var utf8 = ScrcpyClipboardParser()
        #expect(throws: ScrcpyProtocolError.self) { _ = try utf8.append(Data([0,0,0,0,1,255])) }
    }
    @Test func fragmentedWorkerInputAndShutdownRelease() throws {
        var lines = BoundedLineBuffer()
        #expect(try lines.append(Data("input:{\"event\":\"left".utf8)).isEmpty)
        #expect(try lines.append(Data("Up\"}\n".utf8)) == ["input:{\"event\":\"leftUp\"}"])
        var buttons = PressedMouseButtons()
        buttons.record("leftDown")
        #expect(buttons.releaseAll() == ["leftUp"])
        #expect(buttons.releaseAll().isEmpty)
        buttons.record("rightDown"); buttons.record("rightUp")
        #expect(buttons.releaseAll().isEmpty)
    }
}
