import CoreGraphics
import Foundation
import Network

enum ADBBridgeError: Error, LocalizedError {
    case adbNotFound
    case commandFailed(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .adbNotFound:
            return "adb binary not found. Install Android platform-tools or provide an adb path."
        case .commandFailed(let reason):
            return "adb command failed: \(reason)"
        case .invalidOutput(let output):
            return "Unexpected adb output: \(output)"
        }
    }
}

struct ADBBridgeConfiguration {
    var adbPath: String?
    var hostPort: UInt16 = 46001
    var devicePort: UInt16 = 46001
}

final class ADBBridge: @unchecked Sendable {
    let configuration: ADBBridgeConfiguration

    init(configuration: ADBBridgeConfiguration = .init()) {
        self.configuration = configuration
    }

    func prepare() throws {
        let adb = try resolveADBPath()
        _ = try run(adb: adb, arguments: ["start-server"])
        try validateDevicePresence(adb: adb)
        _ = try? run(adb: adb, arguments: ["forward", "--remove", "tcp:\(configuration.hostPort)"])
        _ = try run(adb: adb, arguments: ["forward", "tcp:\(configuration.hostPort)", "tcp:\(configuration.devicePort)"])
        try startCompanionApp(adb: adb)
        try waitForForwardedPort(timeoutSeconds: 5)
    }

    func validateDevicePresence() throws {
        let adb = try resolveADBPath()
        try validateDevicePresence(adb: adb)
    }

    private func validateDevicePresence(adb: String) throws {
        let output = try run(adb: adb, arguments: ["devices"])
        let lines = output
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("\tdevice") }

        guard !lines.isEmpty else {
            throw ADBBridgeError.invalidOutput("No authorized Android device found in adb devices output.")
        }
    }

    func clearForward() throws {
        let adb = try resolveADBPath()
        _ = try? run(adb: adb, arguments: ["forward", "--remove", "tcp:\(configuration.hostPort)"])
    }

    func clearForward(port: UInt16) throws {
        let adb = try resolveADBPath()
        _ = try? run(adb: adb, arguments: ["forward", "--remove", "tcp:\(port)"])
    }

    func resolvedADBPath() throws -> String {
        try resolveADBPath()
    }

    func runShell(arguments: [String]) throws -> String {
        let adb = try resolveADBPath()
        return try run(adb: adb, arguments: ["shell"] + arguments)
    }

    func startCompanionApp() throws {
        try startCompanionApp(adb: try resolveADBPath())
    }

    @discardableResult
    func connectWirelessADB(host: String, port: UInt16 = 5555) throws -> String {
        let adb = try resolveADBPath()
        _ = try? run(adb: adb, arguments: ["start-server"])
        let target = "\(host):\(port)"
        let firstOutput = try? run(adb: adb, arguments: ["connect", target])
        if let firstOutput,
           firstOutput.localizedCaseInsensitiveContains("connected") ||
            firstOutput.localizedCaseInsensitiveContains("already connected") {
            return firstOutput
        }

        _ = try? run(adb: adb, arguments: ["kill-server"])
        _ = try run(adb: adb, arguments: ["start-server"])
        return try run(adb: adb, arguments: ["connect", target])
    }

    func startCompanionApp(serial: String) throws {
        try startCompanionApp(adb: try resolveADBPath(), serial: serial)
    }

    func startExternalDisplayReceiver(port: UInt16) throws {
        let adb = try resolveADBPath()
        _ = try run(adb: adb, arguments: ["start-server"])
        try validateDevicePresence(adb: adb)
        _ = try? run(adb: adb, arguments: ["forward", "--remove", "tcp:\(port)"])
        _ = try run(adb: adb, arguments: ["forward", "tcp:\(port)", "tcp:\(port)"])
        let output = try run(
            adb: adb,
            arguments: [
                "shell",
                "am",
                "start",
                "-W",
                "-n",
                "com.mtog.app/.ExternalDisplayActivity",
                "--ei",
                "port",
                "\(port)"
            ]
        )
        if output.contains("Error") || output.contains("Exception") {
            throw ADBBridgeError.commandFailed(output)
        }
    }

    func queryDisplaySize() throws -> CGSize {
        let output = try runShell(arguments: ["wm", "size"])
        let pattern = /(\d+)x(\d+)/
        guard let match = output.firstMatch(of: pattern),
              let width = Double(match.output.1),
              let height = Double(match.output.2) else {
            throw ADBBridgeError.invalidOutput(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return CGSize(width: width, height: height)
    }

    func queryWirelessIPv4Address() throws -> String {
        let outputs = [
            try? runShell(arguments: ["ip", "-4", "addr", "show", "wlan0"]),
            try? runShell(arguments: ["ip", "-4", "addr"])
        ].compactMap { $0 }

        for output in outputs {
            if let address = Self.firstIPv4Address(in: output) {
                return address
            }
        }

        throw ADBBridgeError.invalidOutput("No Galaxy Wi-Fi IPv4 address found. Connect the tablet to Wi-Fi and retry.")
    }

    private func resolveADBPath() throws -> String {
        for candidate in adbCandidates() {
            if let resolved = executablePathIfAvailable(candidate) {
                return resolved
            }
        }

        if let resolved = resolveFromWhich() {
            return resolved
        }

        throw ADBBridgeError.adbNotFound
    }

    private static func firstIPv4Address(in output: String) -> String? {
        let pattern = /inet\s+(\d+\.\d+\.\d+\.\d+)\//
        for match in output.matches(of: pattern) {
            let address = String(match.output.1)
            if !address.hasPrefix("127.") {
                return address
            }
        }
        return nil
    }

    private func adbCandidates() -> [String] {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let environment = ProcessInfo.processInfo.environment

        return [
            configuration.adbPath,
            environment["ADB_PATH"],
            environment["ANDROID_SDK_ROOT"].flatMap { "\($0)/platform-tools/adb" },
            environment["ANDROID_HOME"].flatMap { "\($0)/platform-tools/adb" },
            "\(homeDirectory)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
    }

    private func executablePathIfAvailable(_ path: String) -> String? {
        let expandedPath = NSString(string: path).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expandedPath) else {
            return nil
        }
        return expandedPath
    }

    private func resolveFromWhich() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["adb"]

        var environment = ProcessInfo.processInfo.environment
        let defaultPath = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")
        environment["PATH"] = environment["PATH"].flatMap { $0.isEmpty ? defaultPath : "\($0):\(defaultPath)" } ?? defaultPath
        task.environment = environment

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private func startCompanionApp(adb: String, serial: String? = nil) throws {
        let selector = serial.map { ["-s", $0] } ?? []
        let launchOutput = try? startBootstrapActivity(
            adb: adb,
            selector: selector,
            action: "com.mtog.app.service.START"
        )

        if let launchOutput,
           launchOutput.contains("Error") || launchOutput.contains("Exception") {
            throw ADBBridgeError.commandFailed(launchOutput)
        }
    }

    @discardableResult
    func requestClipboardSyncService(serial: String? = nil) throws -> String {
        try startBootstrapActivity(
            adb: try resolveADBPath(),
            selector: serial.map { ["-s", $0] } ?? [],
            action: "com.mtog.app.service.SYNC_CLIPBOARD"
        )
    }

    @discardableResult
    private func startBootstrapActivity(adb: String, selector: [String], action: String) throws -> String {
        try run(
            adb: adb,
            arguments: selector + [
                "shell",
                "am",
                "start",
                "-W",
                "-a",
                action,
                "-n",
                "com.mtog.app/.AdbBootstrapActivity"
            ]
        )
    }

    private func waitForForwardedPort(timeoutSeconds: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        repeat {
            if localPortAcceptsConnections(configuration.hostPort) {
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline

        throw ADBBridgeError.commandFailed(
            "Android companion listener is not reachable on localhost:\(configuration.hostPort). Open MtoG on the tablet and retry."
        )
    }

    private func localPortAcceptsConnections(_ port: UInt16) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        let queue = DispatchQueue(label: "com.mtog.adb-port-probe")
        let result = PortProbeResult()

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                result.markReady()
                semaphore.signal()
            case .failed, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 0.4)
        connection.cancel()
        return result.isReady
    }

    @discardableResult
    private func run(adb: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw ADBBridgeError.commandFailed(err.isEmpty ? out : err)
        }

        return out
    }
}

private final class PortProbeResult: @unchecked Sendable {
    private let lock = NSLock()
    private var ready = false

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ready
    }

    func markReady() {
        lock.lock()
        ready = true
        lock.unlock()
    }
}
