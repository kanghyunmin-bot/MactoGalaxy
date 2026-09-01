public struct DisplayPoint: Equatable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public enum DisplayGeometryError: Error {
    case invalidDimensions
    case invalidNormalizedPoint
}

public enum DisplayGeometry {
    public static func mapNormalized(x: Double, y: Double, width: Int, height: Int) throws -> DisplayPoint {
        guard width > 0, height > 0 else { throw DisplayGeometryError.invalidDimensions }
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
            throw DisplayGeometryError.invalidNormalizedPoint
        }
        return DisplayPoint(
            x: Int((x * Double(width)).rounded()),
            y: Int((y * Double(height)).rounded())
        )
    }
}
