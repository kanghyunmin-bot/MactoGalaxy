import Foundation
import Testing
@testable import MtoGCore

struct ClipboardCoreTests {
    @Test @MainActor
    func fakeStoreAndTransportRunBidirectionallyAndStop() {
        let macStore = InMemoryClipboardStore()
        let galaxyStore = InMemoryClipboardStore()
        let macTransport = InMemoryClipboardTransport()
        let galaxyTransport = InMemoryClipboardTransport()
        macTransport.peer = galaxyTransport
        galaxyTransport.peer = macTransport
        let mac = AutomaticClipboardCoordinator(
            store: macStore,
            transport: macTransport,
            sourceID: "mac",
            sessionID: "session-1"
        )
        let galaxy = AutomaticClipboardCoordinator(
            store: galaxyStore,
            transport: galaxyTransport,
            sourceID: "galaxy",
            sessionID: "session-1"
        )
        #expect(mac.start(sessionID: "session-1") == .available)
        #expect(galaxy.start(sessionID: "session-1") == .available)
        macStore.simulateLocalCopy(kind: .text, content: "한글과 emoji 😀")
        #expect(galaxyStore.content == "한글과 emoji 😀")
        galaxyStore.simulateLocalCopy(kind: .url, content: "https://example.test/path")
        #expect(macStore.content == "https://example.test/path")
        for index in 0..<20 {
            macStore.simulateLocalCopy(kind: .text, content: "rapid-\(index)")
        }
        #expect(galaxyStore.content == "rapid-19")

        let stale = try? ClipboardEvent.make(
            sourceID: "mac",
            sessionID: "session-1",
            sequence: 22,
            kind: .text,
            content: "stale"
        )
        #expect(mac.start(sessionID: "session-2") == .available)
        #expect(galaxy.start(sessionID: "session-2") == .available)
        if let stale { macTransport.send(stale) }
        #expect(galaxyStore.content == "rapid-19")
        macTransport.send(
            ClipboardEvent(
                sourceID: "mac",
                sessionID: "session-2",
                sequence: 1,
                kind: .text,
                contentHash: String(repeating: "0", count: 64),
                content: "bad"
            )
        )
        #expect(galaxyStore.content == "rapid-19")
        let maximum = String(repeating: "a", count: ProtocolLimits.automaticClipboardBytes)
        macStore.simulateLocalCopy(kind: .text, content: maximum)
        #expect(galaxyStore.content == maximum)
        macStore.simulateLocalCopy(kind: .text, content: maximum + "a")
        if case .failed = mac.status {} else { Issue.record("oversize copy must fail") }
        #expect(galaxyStore.content == maximum)

        mac.stop()
        galaxy.stop()
        macStore.simulateLocalCopy(kind: .text, content: "after stop")
        #expect(galaxyStore.content == maximum)

        let blocked = AutomaticClipboardCoordinator(
            store: InMemoryClipboardStore(),
            transport: InMemoryClipboardTransport(status: .blocked("no authority")),
            sourceID: "mac",
            sessionID: "session-1"
        )
        #expect(blocked.start(sessionID: "session-1") == .blocked("no authority"))
    }

    @Test
    func fakeBidirectionalTextAndURLSync() throws {
        let mac = ClipboardSyncEngine(sourceID: "mac", sessionID: "session-1")
        let galaxy = ClipboardSyncEngine(sourceID: "galaxy", sessionID: "session-1")

        let korean = try mac.makeLocalEvent(kind: .text, content: "한글과 emoji 😀")
        #expect(galaxy.receive(korean) == .accepted("한글과 emoji 😀"))
        let url = try galaxy.makeLocalEvent(kind: .url, content: "https://example.test/path")
        #expect(mac.receive(url) == .accepted("https://example.test/path"))

        let rapid = try (0..<20).map { try mac.makeLocalEvent(kind: .text, content: "item-\($0)") }
        #expect(rapid.allSatisfy { galaxy.receive($0).isAccepted })
    }

    @Test
    func rejectsLoopReplayBadHashOldSessionAndOversize() throws {
        let mac = ClipboardSyncEngine(sourceID: "mac", sessionID: "session-1")
        let galaxy = ClipboardSyncEngine(sourceID: "galaxy", sessionID: "session-1")
        let local = try mac.makeLocalEvent(kind: .text, content: "same")
        #expect(mac.receive(local) == .localSource)
        #expect(galaxy.receive(local) == .accepted("same"))
        #expect(galaxy.receive(local) == .replayed)

        let badHash = ClipboardEvent(
            sourceID: "mac",
            sessionID: "session-1",
            sequence: local.sequence + 1,
            kind: .text,
            contentHash: String(repeating: "0", count: 64),
            content: "tampered"
        )
        #expect(galaxy.receive(badHash) == .invalidHash)
        let invalid = ClipboardEvent(
            sourceID: "",
            sessionID: "session-1",
            sequence: 0,
            kind: .text,
            contentHash: ClipboardEvent.hash(""),
            content: ""
        )
        #expect(galaxy.receive(invalid) == .invalidEvent)

        galaxy.begin(sessionID: "session-2")
        #expect(galaxy.receive(local) == .staleSession)
        let duplicateContent = try ClipboardEvent.make(
            sourceID: "mac",
            sessionID: "session-2",
            sequence: 1,
            kind: .text,
            content: "same"
        )
        #expect(galaxy.receive(duplicateContent) == .loop)

        let maximum = String(repeating: "a", count: ProtocolLimits.automaticClipboardBytes)
        #expect(try ClipboardEvent.make(sourceID: "mac", sessionID: "session-2", sequence: 2, kind: .text, content: maximum).content == maximum)
        #expect(throws: ClipboardEventError.contentTooLarge) {
            _ = try ClipboardEvent.make(sourceID: "mac", sessionID: "session-2", sequence: 3, kind: .text, content: maximum + "a")
        }
    }
}

private extension ClipboardReceiveResult {
    var isAccepted: Bool {
        if case .accepted = self { return true }
        return false
    }
}
