import MtoGPlatform
import Foundation
import MtoGCore

final class WorkerADBBridge {
    private let videoPort: UInt16
    private let inputPort: UInt16
    private let serial: String
    private let controlSessionID: UUID
    private var adbPath: String?

    init(videoPort: UInt16, inputPort: UInt16, serial: String, controlSessionID: UUID) {
        self.videoPort = videoPort
        self.inputPort = inputPort
        self.serial = serial
        self.controlSessionID = controlSessionID
    }

    func startReceiver() throws {
        let adb = try resolveADBPath()
        adbPath = adb
        _ = try run(adb: adb, arguments: ["start-server"])
        try validateDevicePresence(adb: adb)
        _ = try? run(adb: adb, arguments: ["-s", serial, "forward", "--remove", "tcp:\(videoPort)"])
        _ = try run(adb: adb, arguments: ["-s", serial, "forward", "tcp:\(videoPort)", "tcp:\(videoPort)"])
        _ = try? run(adb: adb, arguments: ["-s", serial, "reverse", "--remove", "tcp:\(inputPort)"])
        _ = try run(adb: adb, arguments: ["-s", serial, "reverse", "tcp:\(inputPort)", "tcp:\(inputPort)"])
        let output = try run(
            adb: adb,
            arguments: [
                "-s", serial, "shell", "am", "start", "-W", "-n", "com.mtog.app/.ExternalDisplayActivity",
                "--ei", "port", "\(videoPort)",
                "--ei", "inputPort", "\(inputPort)",
                "--es", "sessionId", controlSessionID.uuidString
            ]
        )
        if output.contains("Error") || output.contains("Exception") {
            throw WorkerError.adbFailed(output)
        }
    }

    func stop() {
        guard let adb = adbPath else { return }
        _ = try? run(adb: adb, arguments: ["-s", serial, "forward", "--remove", "tcp:\(videoPort)"])
        _ = try? run(adb: adb, arguments: ["-s", serial, "reverse", "--remove", "tcp:\(inputPort)"])
        adbPath = nil
    }

    private func validateDevicePresence(adb: String) throws {
        let output = try run(adb: adb, arguments: ["-s", serial, "get-state"])
        guard output.trimmingCharacters(in: .whitespacesAndNewlines) == "device" else {
            throw WorkerError.deviceMissing
        }
    }

    private func resolveADBPath() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["ADB_PATH"],
            environment["ANDROID_SDK_ROOT"].map { "\($0)/platform-tools/adb" },
            environment["ANDROID_HOME"].map { "\($0)/platform-tools/adb" },
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ].compactMap { $0 }
        for candidate in candidates {
            let path = NSString(string: candidate).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        throw WorkerError.adbNotFound
    }

    @discardableResult
    private func run(adb: String, arguments: [String]) throws -> String {
        let result = try BoundedProcessExecutor.run(
            executableURL: URL(fileURLWithPath: adb),
            arguments: arguments,
            timeout: 15
        )
        let stdout = String(decoding: result.stdout, as: UTF8.self)
        let stderr = String(decoding: result.stderr, as: UTF8.self)
        guard result.status == 0 else {
            throw WorkerError.adbFailed(stderr.isEmpty ? stdout : stderr)
        }
        return stdout
    }
}
