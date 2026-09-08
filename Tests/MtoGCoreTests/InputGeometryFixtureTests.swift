import Foundation
import Testing
@testable import MtoGCore

struct InputGeometryFixtureTests {
    @Test
    func sharedAspectFitVectorsMatch() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/protocol-v2/input/geometry.json"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let vectors = try #require(object["vectors"] as? [[String: Any]])
        for vector in vectors {
            func number(_ key: String) throws -> Double { try #require(vector[key] as? Double) }
            let rect = try DisplayGeometry.aspectFit(
                containerWidth: number("containerWidth"),
                containerHeight: number("containerHeight"),
                contentWidth: number("contentWidth"),
                contentHeight: number("contentHeight")
            )
            let expectedRect = try DisplayRect(
                left: number("left"),
                top: number("top"),
                width: number("width"),
                height: number("height")
            )
            #expect(rect == expectedRect)
            let point = try DisplayGeometry.mapNormalized(
                x: number("normalizedX"), y: number("normalizedY"), in: rect
            )
            let expectedPoint = try DisplayPoint(
                x: Int(number("mappedX")),
                y: Int(number("mappedY"))
            )
            #expect(point == expectedPoint)
        }
    }
}
