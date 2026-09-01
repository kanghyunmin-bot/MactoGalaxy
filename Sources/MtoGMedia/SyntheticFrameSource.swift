import Foundation

public enum SyntheticFramePattern: CaseIterable, Sendable {
    case colorBars
    case gradient
    case grid
    case textLike
    case movingSquare
}

public struct SyntheticFrame: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let sequence: UInt64
    public let presentationTimeUs: UInt64
    public let bgraBytes: Data
}

public final class SyntheticFrameSource {
    public let width: Int
    public let height: Int
    public let framesPerSecond: Int
    private var sequence: UInt64 = 0

    public init(width: Int, height: Int, framesPerSecond: Int = 60) {
        precondition(width > 0 && height > 0 && framesPerSecond > 0)
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
    }

    public func next(pattern: SyntheticFramePattern) -> SyntheticFrame {
        sequence += 1
        var pixels = Data(count: width * height * 4)
        pixels.withUnsafeMutableBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let color = color(pattern: pattern, x: x, y: y, sequence: sequence)
                    let offset = (y * width + x) * 4
                    bytes[offset] = color.2
                    bytes[offset + 1] = color.1
                    bytes[offset + 2] = color.0
                    bytes[offset + 3] = 255
                }
            }
        }
        return SyntheticFrame(
            width: width,
            height: height,
            sequence: sequence,
            presentationTimeUs: (sequence - 1) * 1_000_000 / UInt64(framesPerSecond),
            bgraBytes: pixels
        )
    }

    private func color(pattern: SyntheticFramePattern, x: Int, y: Int, sequence: UInt64) -> (UInt8, UInt8, UInt8) {
        switch pattern {
        case .colorBars:
            let colors: [(UInt8, UInt8, UInt8)] = [
                (255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
                (255, 0, 255), (255, 0, 0), (0, 0, 255), (0, 0, 0)
            ]
            return colors[min(x * colors.count / width, colors.count - 1)]
        case .gradient:
            return (UInt8(x * 255 / max(width - 1, 1)), UInt8(y * 255 / max(height - 1, 1)), 128)
        case .grid:
            return x % 8 == 0 || y % 8 == 0 ? (255, 255, 255) : (24, 24, 24)
        case .textLike:
            let glyph = (x / 3 + y / 5) % 3 == 0 && y % 5 < 4
            return glyph ? (235, 235, 235) : (18, 24, 32)
        case .movingSquare:
            let squareSize = max(2, min(width, height) / 4)
            let originX = Int(sequence % UInt64(max(width - squareSize + 1, 1)))
            let originY = max((height - squareSize) / 2, 0)
            let inside = x >= originX && x < originX + squareSize && y >= originY && y < originY + squareSize
            return inside ? (32, 128, 255) : (8, 8, 8)
        }
    }
}
