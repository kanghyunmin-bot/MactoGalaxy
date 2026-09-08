import Testing
@testable import MtoGCore

struct SessionCoreTests {
    @Test
    func replayGuardBindsSessionTokenAndGeneration() {
        let guardState = SessionReplayGuard()
        guardState.begin(sessionID: "s1", token: "t1", clientNonce: "c1", serverNonce: "n1", generation: 4)
        #expect(guardState.accept(sessionID: "s1", token: "t1", clientNonce: "c1", serverNonce: "n1", sequence: 1, generation: 4))
        #expect(!guardState.accept(sessionID: "s1", token: "t1", clientNonce: "c1", serverNonce: "n1", sequence: 1, generation: 4))
        #expect(!guardState.accept(sessionID: "s1", token: "old", clientNonce: "c1", serverNonce: "n1", sequence: 2, generation: 4))
        #expect(!guardState.accept(sessionID: "s1", token: "t1", clientNonce: "c1", serverNonce: "old", sequence: 2, generation: 4))
        guardState.begin(sessionID: "s2", token: "t2", clientNonce: "c2", serverNonce: "n2", generation: 5)
        #expect(guardState.accept(sessionID: "s2", token: "t2", clientNonce: "c2", serverNonce: "n2", sequence: 1, generation: 5))
        #expect(!guardState.accept(sessionID: "s1", token: "t1", clientNonce: "c1", serverNonce: "n1", sequence: 3, generation: 4))
    }

    @Test
    func reconnectPolicyIsExponentialBoundedAndStopIsTerminal() {
        let policy = ReconnectPolicy(maxAttempts: 8, baseDelaySeconds: 1, maximumDelaySeconds: 16)
        #expect((1...8).compactMap(policy.delaySeconds) == [1, 2, 4, 8, 16, 16, 16, 16])
        #expect(policy.delaySeconds(forAttempt: 9) == nil)

        var machine = SessionStateMachine()
        machine.handle(.start)
        machine.handle(.connected)
        machine.handle(.userStopped)
        machine.handle(.transportFailed)
        #expect(machine.state == .stoppedByUser)
    }

    @Test
    func codecNegotiationPrefersHEVCThenH264() throws {
        let sender = CodecCapabilities(codecs: [.hevc, .h264], maxWidth: 2560, maxHeight: 1600, maxFramesPerSecond: 60)
        let receiver = CodecCapabilities(codecs: [.h264], maxWidth: 1920, maxHeight: 1080, maxFramesPerSecond: 30)
        let result = try CodecNegotiator.negotiate(sender: sender, receiver: receiver)
        #expect(result.codec == .h264)
        #expect(result.width == 1920)
        #expect(result.height == 1080)
        #expect(result.framesPerSecond == 30)
        #expect(throws: CodecNegotiationError.self) {
            _ = try CodecNegotiator.negotiate(
                sender: sender,
                receiver: CodecCapabilities(codecs: [], maxWidth: 1, maxHeight: 1, maxFramesPerSecond: 1)
            )
        }
    }

    @Test
    func geometryAndLatestQueueAreBounded() throws {
        let point = try DisplayGeometry.mapNormalized(x: 0.25, y: 0.75, width: 200, height: 100)
        #expect(throws: DisplayGeometryError.self) {
            _ = try DisplayGeometry.mapNormalized(x: -0.1, y: 0.5, width: 200, height: 100)
        }
        #expect(point == DisplayPoint(x: 50, y: 75))
        #expect(try DisplayGeometry.mapNormalized(x: 0.36, y: 0.36, width: 10, height: 10) == DisplayPoint(x: 4, y: 4))
        var queue = LatestValueQueue<Int>(capacity: 2)
        #expect(queue.append(1) == nil)
        #expect(queue.append(2) == nil)
        #expect(queue.append(3) == 1)
        #expect(queue.values == [2, 3])
    }
}
