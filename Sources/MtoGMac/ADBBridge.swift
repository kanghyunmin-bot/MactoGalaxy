import MtoGPlatform
import CoreGraphics
import Foundation
import MtoGCore
import Network

enum ADBBridgeError: Error, LocalizedError {
    case adbNotFound
    case commandFailed(String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .adbNotFound:
            return "adb를 찾을 수 없습니다. Android platform-tools를 설치하거나 adb 경로를 지정하세요."
        case .commandFailed(let reason):
            return "adb 명령이 실패했습니다: \(reason)"
        case .invalidOutput(let output):
            return "예상하지 못한 adb 응답입니다: \(output)"
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
    private let selectionLock = NSLock()
    private var selectedSerial: String?

    init(configuration: ADBBridgeConfiguration = .init()) {
        self.configuration = configuration
    }

    func prepare() throws {
        let adb = try resolveADBPath()
        _ = try run(adb: adb, arguments: ["start-server"])
        let serial = try selectAuthorizedDevice(adb: adb)
        _ = try? run(adb: adb, arguments: ["-s", serial, "forward", "--remove", "tcp:\(configuration.hostPort)"])
        _ = try run(adb: adb, arguments: ["-s", serial, "forward", "tcp:\(configuration.hostPort)", "tcp:\(configuration.devicePort)"])
        try startCompanionApp(adb: adb, serial: serial)
        try waitForForwardedPort(timeoutSeconds: 5)
    }

    func validateDevicePresence() throws {
        _ = try selectAuthorizedDevice(adb: try resolveADBPath())
    }

    @discardableResult
    func selectAuthorizedDevice(preferredSerial: String? = nil) throws -> String {
        try selectAuthorizedDevice(adb: resolveADBPath(), preferredSerial: preferredSerial)
    }

    var selectedDeviceSerial: String? {
        selectionLock.lock(); defer { selectionLock.unlock() }
        return selectedSerial
    }

    func clearForward() throws {
        let serial = try requireSelectedSerial()
        _ = try? run(
            adb: resolveADBPath(),
            arguments: ["-s", serial, "forward", "--remove", "tcp:\(configuration.hostPort)"]
        )
    }

    func clearForward(port: UInt16) throws {
        let serial = try requireSelectedSerial()
        _ = try? run(
            adb: resolveADBPath(),
            arguments: ["-s", serial, "forward", "--remove", "tcp:\(port)"]
        )
    }

    func clearExternalDisplayMappings(serial: String, videoPort: UInt16 = 46002, inputPort: UInt16 = 46003) {
        guard let adb = try? resolveADBPath() else { return }
        _ = try? run(adb: adb, arguments: ["-s", serial, "forward", "--remove", "tcp:\(videoPort)"])
        _ = try? run(adb: adb, arguments: ["-s", serial, "reverse", "--remove", "tcp:\(inputPort)"])
    }

    func resolvedADBPath() throws -> String {
        try resolveADBPath()
    }

    func runShell(arguments: [String]) throws -> String {
        let adb = try resolveADBPath()
        let serial = try selectAuthorizedDevice(adb: adb)
        return try run(adb: adb, arguments: ["-s", serial, "shell"] + arguments)
    }

    func startCompanionApp() throws {
        let adb = try resolveADBPath()
        try startCompanionApp(adb: adb, serial: selectAuthorizedDevice(adb: adb))
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
            setSelectedSerial(target)
            return firstOutput
        }

        _ = try? run(adb: adb, arguments: ["kill-server"])
        _ = try run(adb: adb, arguments: ["start-server"])
        let output = try run(adb: adb, arguments: ["connect", target])
        guard output.localizedCaseInsensitiveContains("connected") else {
            throw ADBBridgeError.commandFailed(output)
        }
        setSelectedSerial(target)
        return output
    }

    func startCompanionApp(serial: String) throws {
        setSelectedSerial(serial)
        try startCompanionApp(adb: try resolveADBPath(), serial: serial)
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

        throw ADBBridgeError.invalidOutput("갤럭시의 Wi-Fi IPv4 주소를 찾지 못했습니다. 태블릿을 개인 Wi-Fi에 연결한 뒤 다시 시도하세요.")
    }

    private func selectAuthorizedDevice(adb: String, preferredSerial: String? = nil) throws -> String {
        selectionLock.lock()
        let existing = selectedSerial
        selectionLock.unlock()
        let devices = ADBDeviceParser.parse(try run(adb: adb, arguments: ["devices", "-l"]))
        do {
            let selected = try ADBDeviceSelector.select(
                devices: devices,
                preferredSerial: preferredSerial ?? existing
            ).serial
            setSelectedSerial(selected)
            return selected
        } catch let error as ADBDeviceSelectionError {
            switch error {
            case .noAuthorizedDevice:
                throw ADBBridgeError.invalidOutput("허용된 Android 기기를 찾지 못했습니다")
            case .multipleAuthorized(let serials):
                throw ADBBridgeError.invalidOutput("여러 Android 기기가 연결됨: \(serials.joined(separator: ", "))")
            case .preferredUnavailable(let serial):
                throw ADBBridgeError.invalidOutput("선택한 Android 기기를 사용할 수 없음: \(serial)")
            }
        }
    }

    private func setSelectedSerial(_ serial: String) {
        selectionLock.lock(); selectedSerial = serial; selectionLock.unlock()
    }

    private func requireSelectedSerial() throws -> String {
        guard let serial = selectedDeviceSerial else {
            throw ADBBridgeError.invalidOutput("정리할 Android 기기 serial이 없습니다")
        }
        return serial
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
        guard let result = try? BoundedProcessExecutor.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/which"),
            arguments: ["adb"],
            environment: environment,
            timeout: 2
        ), result.status == 0 else { return nil }

        let data = result.stdout
        let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    private func startCompanionApp(adb: String, serial: String) throws {
        let selector = ["-s", serial]
        let launchOutput = try startBootstrapActivity(
            adb: adb,
            selector: selector,
            action: "com.mtog.app.service.START"
        )

        if launchOutput.contains("Error") || launchOutput.contains("Exception") {
            throw ADBBridgeError.commandFailed(launchOutput)
        }
    }

    @discardableResult
    func requestClipboardSyncService(serial: String? = nil) throws -> String {
        let adb = try resolveADBPath()
        let selected = try selectAuthorizedDevice(adb: adb, preferredSerial: serial)
        return try startBootstrapActivity(
            adb: adb,
            selector: ["-s", selected],
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
            "갤럭시 앱 수신 포트(localhost:\(configuration.hostPort))에 연결하지 못했습니다. 태블릿에서 MtoG를 열고 다시 시도하세요."
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
        let result = try BoundedProcessExecutor.run(
            executableURL: URL(fileURLWithPath: adb),
            arguments: arguments,
            timeout: 15
        )
        let out = String(decoding: result.stdout, as: UTF8.self)
        let err = String(decoding: result.stderr, as: UTF8.self)

        guard result.status == 0 else {
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
