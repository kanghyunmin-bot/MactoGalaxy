import CryptoKit
import Foundation
import MtoGCore
import Testing
@testable import MtoGPlatform

@MainActor
struct ScrcpyAdapterTests {
    private func waitUntil(_ predicate: () -> Bool, timeout: Double = 5) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return predicate()
    }
    @Test func productionAdapterUsesFakeExecutableAndSocket() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/scrcpy/fake-adb.py")
        let executable = root.appendingPathComponent("fake-adb.py")
        try FileManager.default.copyItem(at: fixture, to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let server = root.appendingPathComponent("server")
        let content = Data("fixture server".utf8)
        try content.write(to: server)
        var config = ScrcpyClipboardConfiguration(adbURL: executable, serverURL: server)
        // Internal test seam changes only the expected fixture hash, not transport or lifecycle.
        config.expectedSHA256 = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let adapter = ShellClipboardTransport()
        let session = UUID().uuidString
        var received: [ClipboardEvent] = []
        adapter.start(configuration: config, serial: "FAKE-SERIAL", sessionID: session, trusted: true)
        adapter.receiveHandler = { received.append($0) }
        #expect(await waitUntil { !received.isEmpty })
        #expect(adapter.status == .available)
        #expect(received.first?.content == "Galaxy 한글😀")
        let local = try ClipboardEvent.make(sourceID: "mac", sessionID: session, sequence: 1, kind: .url, content: "https://example.com/한글😀")
        adapter.send(local)
        #expect(await waitUntil { FileManager.default.fileExists(atPath: root.appendingPathComponent("write-size").path) })
        try? await Task.sleep(for: .milliseconds(650))
        #expect(received.count == 1) // readback is confirmation, not a reflection
        adapter.send(try .make(sourceID: "mac", sessionID: UUID().uuidString, sequence: 2, kind: .text, content: "stale"))
        #expect(try String(contentsOf: root.appendingPathComponent("write-size"), encoding: .utf8) == String(local.content.utf8.count))
        try Data().write(to: root.appendingPathComponent("deny"))
        #expect(await waitUntil {
            if case .permissionRequired = adapter.status { return true }; return false
        })
        try FileManager.default.removeItem(at: root.appendingPathComponent("deny"))
        #expect(await waitUntil { adapter.status == .available })
        adapter.send(try .make(sourceID: "mac", sessionID: session, sequence: 2, kind: .text, content: "recovered"))
        #expect(await waitUntil {
            (try? String(contentsOf: root.appendingPathComponent("write-size"), encoding: .utf8)) == "9"
        })
        try? await Task.sleep(for: .milliseconds(650))
        try Data().write(to: root.appendingPathComponent("reject-write"))
        adapter.send(try .make(sourceID: "mac", sessionID: session, sequence: 3, kind: .text, content: "not-applied"))
        #expect(await waitUntil {
            if case .failed = adapter.status { return true }; return false
        })
        try? await Task.sleep(for: .milliseconds(650))
        #expect(received.count == 1) // no remote overwrite after terminal verification failure
        adapter.stop()
        #expect(adapter.status == .stopped)
        #expect(await waitUntil { FileManager.default.fileExists(atPath: root.appendingPathComponent("cleaned").path) })
        #expect(received.count == 1)
        let commands = try String(contentsOf: root.appendingPathComponent("commands.jsonl"), encoding: .utf8)
        #expect(commands.contains("tcp:0"))
        #expect(commands.contains("--remove"))
        #expect(!commands.contains(local.content))
    }
    @Test func trustAndVersionFailBeforeLaunching() {
        let adapter = ShellClipboardTransport()
        let config = ScrcpyClipboardConfiguration(adbURL: URL(fileURLWithPath: "/nonexistent-adb"), serverURL: URL(fileURLWithPath: "/nonexistent-server"))
        adapter.start(configuration: config, serial: "FAKE", sessionID: UUID().uuidString, trusted: false)
        if case .blocked = adapter.status {} else { Issue.record("Untrusted session accepted") }
        adapter.start(configuration: config, serial: "FAKE", sessionID: UUID().uuidString, trusted: true)
        if case .unsupported = adapter.status {} else { Issue.record("Unpinned server accepted") }
    }
}
