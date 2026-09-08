import Darwin
import Foundation
import MtoGCore
import Testing
@testable import MtoGExternalDisplayWorker

@Test func retriesEarlyEOFBeforeAndroidCapabilities() throws {
    let listener = socket(AF_INET, SOCK_STREAM, 0)
    #expect(listener >= 0)
    defer { Darwin.close(listener) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    #expect(bound == 0)
    #expect(listen(listener, 2) == 0)
    var size = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &size) }
    }
    let session = UUID()
    let packet = try VideoPacketCodec.encode(VideoPacket(
        kind: .control, codec: .h264, flags: 0, sessionID: session,
        sequence: 1, presentationTimeUs: 0, width: 1920, height: 1200,
        controlCode: .capabilities,
        payload: Data([3, 0, 0, 7, 128, 0, 0, 4, 176, 0, 60])
    ))
    let finished = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        defer { finished.signal() }
        // Simulate an ADB forward whose Android endpoint has not started.
        let early = accept(listener, nil, nil)
        if early >= 0 { Darwin.close(early) }
        let ready = accept(listener, nil, nil)
        guard ready >= 0 else { return }
        defer { Darwin.close(ready) }
        var noSignal: Int32 = 1
        setsockopt(ready, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        _ = packet.withUnsafeBytes { Darwin.send(ready, $0.baseAddress, $0.count, 0) }
    }
    let sender = VideoStreamSender(port: UInt16(bigEndian: address.sin_port), codec: .h264,
        width: 1920, height: 1200, sessionID: session)
    defer { sender.close() }
    try sender.connect(timeoutSeconds: 1)
    let capabilities = try sender.receiveCapabilities(timeoutSeconds: 2)
    #expect(capabilities.maxWidth == 1920)
    #expect(capabilities.maxHeight == 1200)
    #expect(capabilities.codecs.contains(.hevc))
    #expect(finished.wait(timeout: .now() + 1) == .success)
}
