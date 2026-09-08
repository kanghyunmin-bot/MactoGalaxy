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

public struct DisplayRect: Equatable, Sendable {
    public let left: Double
    public let top: Double
    public let width: Double
    public let height: Double

    public init(left: Double, top: Double, width: Double, height: Double) {
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }
}

public enum DisplayGeometry {
    public static func aspectFit(
        containerWidth: Double,
        containerHeight: Double,
        contentWidth: Double,
        contentHeight: Double
    ) throws -> DisplayRect {
        guard containerWidth > 0, containerHeight > 0, contentWidth > 0, contentHeight > 0 else {
            throw DisplayGeometryError.invalidDimensions
        }
        let scale = min(containerWidth / contentWidth, containerHeight / contentHeight)
        let width = contentWidth * scale
        let height = contentHeight * scale
        return DisplayRect(
            left: (containerWidth - width) / 2,
            top: (containerHeight - height) / 2,
            width: width,
            height: height
        )
    }

    public static func mapNormalized(x: Double, y: Double, in rect: DisplayRect) throws -> DisplayPoint {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else {
            throw DisplayGeometryError.invalidNormalizedPoint
        }
        return DisplayPoint(
            x: Int((rect.left + x * rect.width).rounded()),
            y: Int((rect.top + y * rect.height).rounded())
        )
    }

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
