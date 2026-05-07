import Foundation

final class ScrcpyMirrorBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.mtog.scrcpy-mirror", qos: .userInitiated)
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var isStopping = false

    var statusHandler: ((String) -> Void)?
    var stateHandler: ((Bool) -> Void)?

    var isRunning: Bool {
        queue.sync { process?.isRunning == true }
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.process?.isRunning == true {
                self.reportStatus("Mirror is already running")
                self.reportState(true)
                return
            }
            self.isStopping = false

            guard let scrcpyURL = self.resolveExecutableURL(name: "scrcpy") else {
                self.reportStatus("scrcpy not found. Install with: brew install scrcpy")
                self.reportState(false)
                return
            }

            guard let serial = self.detectPreferredUsbAdbSerial() else {
                self.reportStatus("No authorized USB Galaxy found. Connect USB-C and allow USB debugging.")
                self.reportState(false)
                return
            }

            let arguments = [
                "--serial=\(serial)",
                "--keyboard=sdk",
                "--mouse=sdk",
                "--mouse-bind=++++:++++",
                "--shortcut-mod=lalt,ralt",
                "--no-clipboard-autosync",
                "--video-codec=h264",
                "--video-bit-rate=32M",
                "--max-fps=60",
                "--max-size=0",
                "--render-driver=metal",
                "--stay-awake",
                "--no-audio",
                "--window-title=MtoG Galaxy Mirror"
            ]

            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = scrcpyURL
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.handleOutputData(handle.availableData, isError: false)
            }
            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.handleOutputData(handle.availableData, isError: true)
            }

            process.terminationHandler = { [weak self] process in
                guard let self else { return }
                self.queue.async {
                    self.process = nil
                    self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                    self.errorPipe?.fileHandleForReading.readabilityHandler = nil
                    if self.isStopping || process.terminationStatus == 0 {
                        self.reportStatus("Mirror stopped")
                    } else {
                        self.reportStatus("Mirror stopped with scrcpy exit \(process.terminationStatus)")
                    }
                    self.isStopping = false
                    self.reportState(false)
                }
            }

            do {
                try process.run()
                self.process = process
                self.outputPipe = outputPipe
                self.errorPipe = errorPipe
                self.reportStatus("Mirror running over USB: \(serial)")
                self.reportState(true)
            } catch {
                self.reportStatus("Mirror failed: \(error.localizedDescription)")
                self.reportState(false)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isStopping = true
            self.process?.terminate()
            self.process = nil
            self.reportStatus("Stopping mirror")
            self.reportState(false)
        }
    }

    private func handleOutputData(_ data: Data, isError: Bool) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let lastLine = lines.last else { return }
        guard let status = userFacingStatus(from: lastLine, isError: isError) else { return }
        reportStatus(status)
    }

    private func userFacingStatus(from line: String, isError: Bool) -> String? {
        if let range = line.range(of: "INFO: Device:") {
            let device = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return device.isEmpty ? "Mirror running" : "Mirror running on \(device)"
        }

        if let range = line.range(of: "ERROR:") {
            let message = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "scrcpy error" : "scrcpy error: \(message)"
        }

        if let range = line.range(of: "WARN:") {
            let message = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "scrcpy warning" : "scrcpy warning: \(message)"
        }

        if isError, !line.contains("INFO:") {
            return "scrcpy: \(line)"
        }

        return nil
    }

    private struct ADBDevice {
        let serial: String
        let state: String
        let detail: String

        var isUsable: Bool { state == "device" }
        var isUSB: Bool { detail.contains("usb:") }
    }

    private func detectPreferredUsbAdbSerial() -> String? {
        let devices = adbDevices()
        if let usbDevice = devices.first(where: { $0.isUsable && $0.isUSB }) {
            return usbDevice.serial
        }
        return devices.first(where: { $0.isUsable })?.serial
    }

    private func adbDevices() -> [ADBDevice] {
        guard let adbURL = resolveExecutableURL(name: "adb") else { return [] }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = adbURL
        process.arguments = ["devices", "-l"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line -> ADBDevice? in
                let parts = line.split(whereSeparator: \.isWhitespace)
                guard parts.count >= 2 else { return nil }
                return ADBDevice(
                    serial: String(parts[0]),
                    state: String(parts[1]),
                    detail: parts.dropFirst(2).joined(separator: " ")
                )
            }
    }

    private func resolveExecutableURL(name: String) -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty,
            fileManager.isExecutableFile(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private func reportStatus(_ status: String) {
        statusHandler?(status)
    }

    private func reportState(_ running: Bool) {
        stateHandler?(running)
    }
}
