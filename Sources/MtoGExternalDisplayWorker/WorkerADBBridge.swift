import Foundation

final class WorkerADBBridge {
    private let videoPort: UInt16
    private let inputPort: UInt16
    private var adbPath: String?

    init(videoPort: UInt16, inputPort: UInt16) {
        self.videoPort = videoPort
        self.inputPort = inputPort
    }

    func startReceiver() throws {
        let adb = try resolveADBPath()
        adbPath = adb
        _ = try run(adb: adb, arguments: ["start-server"])
        try validateDevicePresence(adb: adb)
        _ = try? run(adb: adb, arguments: ["forward", "--remove", "tcp:\(videoPort)"])
        _ = try run(adb: adb, arguments: ["forward", "tcp:\(videoPort)", "tcp:\(videoPort)"])
        _ = try? run(adb: adb, arguments: ["reverse", "--remove", "tcp:\(inputPort)"])
        _ = try run(adb: adb, arguments: ["reverse", "tcp:\(inputPort)", "tcp:\(inputPort)"])
        let output = try run(
            adb: adb,
            arguments: [
                "shell", "am", "start", "-W", "-n", "com.mtog.app/.ExternalDisplayActivity",
                "--ei", "port", "\(videoPort)", "--ei", "inputPort", "\(inputPort)"
            ]
        )
        if output.contains("Error") || output.contains("Exception") {
            throw WorkerError.adbFailed(output)
        }
    }

    func stop() {
        guard let adb = adbPath else { return }
        _ = try? run(adb: adb, arguments: ["forward", "--remove", "tcp:\(videoPort)"])
        _ = try? run(adb: adb, arguments: ["reverse", "--remove", "tcp:\(inputPort)"])
        adbPath = nil
    }

    private func validateDevicePresence(adb: String) throws {
        let output = try run(adb: adb, arguments: ["devices"])
        guard output.split(separator: "\n").contains(where: { $0.contains("\tdevice") }) else {
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw WorkerError.adbFailed(stderr.isEmpty ? stdout : stderr)
        }
        return stdout
    }
}
