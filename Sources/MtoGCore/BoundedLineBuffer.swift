import Foundation

public struct BoundedLineBuffer {
    private var pending = Data()
    public init() {}
    public mutating func append(_ data: Data) throws -> [String] {
        var lines: [String] = []
        for byte in data {
            if byte == 10 {
                guard let text = String(data: pending, encoding: .utf8) else { throw ScrcpyProtocolError.invalidUTF8 }
                lines.append(text); pending.removeAll(keepingCapacity: true)
            } else {
                guard pending.count < 65536 else { throw ScrcpyProtocolError.oversized }
                pending.append(byte)
            }
        }
        return lines
    }
}

public struct PressedMouseButtons {
    private var pressed: Set<String> = []
    public init() {}
    public mutating func record(_ event: String) {
        if event == "leftDown" { pressed.insert("leftUp") }
        if event == "rightDown" { pressed.insert("rightUp") }
        if event.hasSuffix("Up") { pressed.remove(event) }
    }
    public mutating func releaseAll() -> [String] {
        defer { pressed.removeAll() }
        return pressed.sorted()
    }
}
