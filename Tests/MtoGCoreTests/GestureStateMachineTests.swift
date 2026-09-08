import Foundation
import Testing
@testable import MtoGCore

private struct GestureFixture: Decodable {
    struct Vector: Decodable {
        let name: String
        let events: [GestureEvent]
        let commands: [GestureCommand]
    }
    let vectors: [Vector]
}

struct GestureStateMachineTests {
    @Test
    func sharedGestureVectorsMatch() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/protocol-v2/input/gestures.json"))
        let fixture = try JSONDecoder().decode(GestureFixture.self, from: data)

        for vector in fixture.vectors {
            var machine = GestureStateMachine()
            let commands = vector.events.flatMap { machine.process($0) }
            #expect(commands == vector.commands, "gesture vector failed: \(vector.name)")
        }
    }
}
