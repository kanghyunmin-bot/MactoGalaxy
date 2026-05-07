import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class ExternalDisplayInputSynthesizer {
    var permissionFailureHandler: (() -> Void)?

    private var didReportMissingAccessibility = false

    func handleInputPayload(_ payload: String) {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = object["kind"] as? String else {
            return
        }

        switch kind {
        case "move":
            guard let point = point(from: object) else { return }
            moveCursor(to: point)
        case "mouse":
            guard let eventName = object["event"] as? String,
                  let point = point(from: object) else { return }
            postMouse(eventName: eventName, point: point)
        case "scroll":
            let wheelX = int32(object["wheelX"])
            let wheelY = int32(object["wheelY"])
            postScroll(wheelX: wheelX, wheelY: wheelY)
        default:
            break
        }
    }

    private func point(from object: [String: Any]) -> CGPoint? {
        guard let x = double(object["x"]),
              let y = double(object["y"]) else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    private func moveCursor(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    }

    private func postMouse(eventName: String, point: CGPoint) {
        guard accessibilityIsTrusted() else { return }

        let mapping = mouseMapping(for: eventName)
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: mapping.type,
            mouseCursorPosition: point,
            mouseButton: mapping.button
        ) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }

    private func postScroll(wheelX: Int32, wheelY: Int32) {
        guard accessibilityIsTrusted(), wheelX != 0 || wheelY != 0 else { return }

        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: wheelY,
            wheel2: wheelX,
            wheel3: 0
        ) else {
            return
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.post(tap: .cghidEventTap)
    }

    private func accessibilityIsTrusted() -> Bool {
        if AXIsProcessTrusted() {
            didReportMissingAccessibility = false
            return true
        }

        if !didReportMissingAccessibility {
            didReportMissingAccessibility = true
            permissionFailureHandler?()
        }
        return false
    }

    private func mouseMapping(for eventName: String) -> (type: CGEventType, button: CGMouseButton) {
        switch eventName {
        case "leftDown":
            return (.leftMouseDown, .left)
        case "leftUp":
            return (.leftMouseUp, .left)
        case "leftDragged":
            return (.leftMouseDragged, .left)
        case "rightDown":
            return (.rightMouseDown, .right)
        case "rightUp":
            return (.rightMouseUp, .right)
        case "rightDragged":
            return (.rightMouseDragged, .right)
        default:
            return (.mouseMoved, .left)
        }
    }

    private func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let double = value as? Double {
            return double
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private func int32(_ value: Any?) -> Int32 {
        if let number = value as? NSNumber {
            return number.int32Value
        }
        if let int = value as? Int {
            return Int32(int)
        }
        if let string = value as? String, let int = Int32(string) {
            return int
        }
        return 0
    }
}
