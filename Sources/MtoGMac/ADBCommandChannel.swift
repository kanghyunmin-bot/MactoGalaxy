import CoreGraphics
import Foundation

final class ADBCommandChannel: @unchecked Sendable {
    private let bridge: ADBBridge
    private let queue = DispatchQueue(label: "com.mtog.adb-command-channel", qos: .userInitiated)

    var errorHandler: ((String) -> Void)?

    init(bridge: ADBBridge = ADBBridge()) {
        self.bridge = bridge
    }

    func activate() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.bridge.validateDevicePresence()
            } catch {
                self.report(error)
            }
        }
    }

    func deactivate() {
        // One-shot adb invocations do not need a persistent shell session.
    }

    func queryDisplaySize() -> CGSize? {
        do {
            return try bridge.queryDisplaySize()
        } catch {
            report(error)
            return nil
        }
    }

    func sendKeyEvent(_ key: String) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                _ = try self.bridge.runShell(arguments: ["input", "keyevent", key])
            } catch {
                self.report(error)
            }
        }
    }

    func sendKeyCombination(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            do {
                _ = try self.bridge.runShell(arguments: ["input", "keycombination"] + keys)
            } catch {
                self.report(error)
            }
        }
    }

    func sendText(_ text: String) {
        let normalized = text
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        guard !normalized.isEmpty else { return }

        let payload = normalized.replacingOccurrences(of: " ", with: "%s")
        queue.async { [weak self] in
            guard let self else { return }
            do {
                _ = try self.bridge.runShell(arguments: ["input", "text", payload])
            } catch {
                self.report(error)
            }
        }
    }

    func sendTap(x: Int, y: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                _ = try self.bridge.runShell(arguments: ["input", "tap", String(x), String(y)])
            } catch {
                self.report(error)
            }
        }
    }

    func sendSwipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                _ = try self.bridge.runShell(
                    arguments: [
                        "input", "swipe",
                        String(x1), String(y1),
                        String(x2), String(y2),
                        String(durationMs)
                    ]
                )
            } catch {
                self.report(error)
            }
        }
    }

    func sendScroll(x: Int, y: Int, vertical: Int, horizontal: Int) {
        guard vertical != 0 || horizontal != 0 else { return }

        var arguments = ["input", "mouse", "scroll", String(x), String(y)]
        if vertical != 0 {
            arguments += ["--axis", "VSCROLL,\(vertical)"]
        }
        if horizontal != 0 {
            arguments += ["--axis", "HSCROLL,\(horizontal)"]
        }
        let commandArguments = arguments

        queue.async { [weak self] in
            guard let self else { return }
            do {
                _ = try self.bridge.runShell(arguments: commandArguments)
            } catch {
                self.report(error)
            }
        }
    }

    private func report(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        errorHandler?(message)
    }

    private func report(_ message: String) {
        errorHandler?(message)
    }
}
