import Foundation

public struct GestureEvent: Codable, Equatable, Sendable {
    public let kind: String
    public let timeMs: Int64
    public let pointers: Int
    public let x: Double
    public let y: Double

    public init(kind: String, timeMs: Int64, pointers: Int, x: Double, y: Double) {
        self.kind = kind
        self.timeMs = timeMs
        self.pointers = pointers
        self.x = x
        self.y = y
    }
}

public struct GestureCommand: Codable, Equatable, Sendable {
    public let kind: String
    public let x: Double?
    public let y: Double?
    public let deltaX: Double?
    public let deltaY: Double?
    public let button: String?
    public let tapCount: Int?

    public init(
        kind: String,
        x: Double? = nil,
        y: Double? = nil,
        deltaX: Double? = nil,
        deltaY: Double? = nil,
        button: String? = nil,
        tapCount: Int? = nil
    ) {
        self.kind = kind
        self.x = x
        self.y = y
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.button = button
        self.tapCount = tapCount
    }
}

public struct GestureStateMachine: Sendable {
    public static let doubleTapDelayMs: Int64 = 480
    public static let longPressDelayMs: Int64 = 700

    private let tapMoveTolerance = 0.025
    private let doubleTapTolerance = 0.04
    private let tapMaxDurationMs: Int64 = 350

    private var down: GestureEvent?
    private var dragging = false
    private var longPressFired = false
    private var pendingTap: GestureEvent?
    private var twoFingerPoint: (x: Double, y: Double)?

    public init() {}

    public mutating func process(_ event: GestureEvent) -> [GestureCommand] {
        var commands: [GestureCommand] = []
        if event.kind == "tick" {
            commands += flushTimers(at: event.timeMs)
            return commands
        }

        if let pendingTap,
           event.timeMs > pendingTap.timeMs + Self.doubleTapDelayMs {
            commands += emitPendingTap()
        }

        if event.pointers >= 2 || event.kind == "pointerDown" || event.kind == "pointerUp" {
            commands += processTwoFinger(event)
            return commands
        }

        switch event.kind {
        case "down":
            if let pendingTap, distance(pendingTap, event) > doubleTapTolerance {
                commands += emitPendingTap()
            }
            down = event
            dragging = false
            longPressFired = false
            twoFingerPoint = nil
        case "move":
            guard let down else { break }
            if longPressFired {
                break
            } else if dragging {
                commands.append(.init(kind: "drag", x: event.x, y: event.y, button: "left"))
            } else if distance(down, event) > tapMoveTolerance {
                commands += emitPendingTap()
                dragging = true
                commands.append(.init(kind: "buttonDown", x: down.x, y: down.y, button: "left"))
                commands.append(.init(kind: "drag", x: event.x, y: event.y, button: "left"))
            } else {
                commands += fireLongPressIfNeeded(at: event.timeMs)
            }
        case "up":
            if dragging {
                commands.append(.init(kind: "buttonUp", x: event.x, y: event.y, button: "left"))
            } else if !longPressFired,
                      let down,
                      event.timeMs - down.timeMs <= tapMaxDurationMs,
                      distance(down, event) <= tapMoveTolerance {
                if let previous = pendingTap,
                   event.timeMs <= previous.timeMs + Self.doubleTapDelayMs,
                   distance(previous, event) <= doubleTapTolerance {
                    pendingTap = nil
                    commands.append(.init(kind: "click", x: event.x, y: event.y, button: "left", tapCount: 2))
                } else {
                    commands += emitPendingTap()
                    pendingTap = event
                }
            }
            clearContact()
        case "cancel":
            if dragging {
                commands.append(.init(kind: "buttonUp", x: event.x, y: event.y, button: "left"))
            }
            reset()
        default:
            break
        }
        return commands
    }

    public mutating func cancel(atX x: Double, y: Double, timeMs: Int64) -> [GestureCommand] {
        process(.init(kind: "cancel", timeMs: timeMs, pointers: 1, x: x, y: y))
    }

    private mutating func flushTimers(at timeMs: Int64) -> [GestureCommand] {
        var commands = fireLongPressIfNeeded(at: timeMs)
        if let pendingTap, timeMs > pendingTap.timeMs + Self.doubleTapDelayMs {
            commands += emitPendingTap()
        }
        return commands
    }

    private mutating func fireLongPressIfNeeded(at timeMs: Int64) -> [GestureCommand] {
        guard let down,
              !dragging,
              !longPressFired,
              timeMs >= down.timeMs + Self.longPressDelayMs else { return [] }
        longPressFired = true
        var commands = emitPendingTap()
        commands.append(.init(kind: "click", x: down.x, y: down.y, button: "right", tapCount: 1))
        return commands
    }

    private mutating func emitPendingTap() -> [GestureCommand] {
        guard let pendingTap else { return [] }
        self.pendingTap = nil
        return [.init(kind: "click", x: pendingTap.x, y: pendingTap.y, button: "left", tapCount: 1)]
    }

    private mutating func processTwoFinger(_ event: GestureEvent) -> [GestureCommand] {
        var commands: [GestureCommand] = []
        if dragging {
            commands.append(.init(kind: "buttonUp", x: event.x, y: event.y, button: "left"))
        }
        clearContact()
        commands += emitPendingTap()
        switch event.kind {
        case "pointerDown", "down":
            twoFingerPoint = (event.x, event.y)
        case "move":
            if let previous = twoFingerPoint {
                commands.append(.init(
                    kind: "scroll",
                    deltaX: rounded(previous.x - event.x),
                    deltaY: rounded(previous.y - event.y)
                ))
            }
            twoFingerPoint = (event.x, event.y)
        case "pointerUp", "up", "cancel":
            twoFingerPoint = nil
        default:
            break
        }
        return commands
    }

    private mutating func clearContact() {
        down = nil
        dragging = false
        longPressFired = false
    }

    private mutating func reset() {
        clearContact()
        pendingTap = nil
        twoFingerPoint = nil
    }

    private func distance(_ lhs: GestureEvent, _ rhs: GestureEvent) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func rounded(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }
}
