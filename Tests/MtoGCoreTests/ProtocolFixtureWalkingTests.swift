import Foundation
import Testing
@testable import MtoGCore

struct ProtocolFixtureWalkingTests {
    @Test
    func sharedManifestMatchesCoreLimits() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = repositoryRoot.appendingPathComponent("Fixtures/protocol-v2/manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let limits = try #require(object["limits"] as? [String: Any])

        #expect(object["protocolVersion"] as? Int == ProtocolLimits.version)
        #expect(limits["controlPayloadBytes"] as? Int == ProtocolLimits.controlPayloadBytes)
        #expect(limits["videoPayloadBytes"] as? Int == ProtocolLimits.videoPayloadBytes)
        #expect(limits["automaticClipboardBytes"] as? Int == ProtocolLimits.automaticClipboardBytes)
    }
}
