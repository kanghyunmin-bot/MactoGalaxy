import Foundation

final class VirtualDisplayBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.mtog.virtual-display-supervisor", qos: .userInitiated)
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    var statusHandler: ((String) -> Void)?
    var stateHandler: ((Bool) -> Void)?
    var inputHandler: ((String) -> Void)?

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.process?.isRunning == true {
                self.reportStatus("External display helper is already running")
                self.reportState(true)
                return
            }

            guard let helperURL = self.resolveHelperURL() else {
                self.reportStatus("External display failed: helper executable is missing")
                self.reportState(false)
                return
            }

            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = helperURL
            process.arguments = []
            process.standardOutput = stdout
            process.standardError = stderr

            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.handleOutput(handle.availableData, isError: false)
            }
            stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.handleOutput(handle.availableData, isError: true)
            }

            process.terminationHandler = { [weak self] terminatedProcess in
                guard let bridge = self else { return }
                bridge.queue.async { [weak bridge] in
                    bridge?.handleTermination(terminatedProcess)
                }
            }

            do {
                try process.run()
                self.process = process
                self.outputPipe = stdout
                self.errorPipe = stderr
                self.reportState(true)
                self.reportStatus("External display helper started")
            } catch {
                self.cleanupPipeHandlers()
                self.reportState(false)
                self.reportStatus("External display failed: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopLocked(waitForExit: false)
        }
    }

    func stopImmediately() {
        queue.sync {
            stopLocked(waitForExit: true)
        }
    }

    private func handleTermination(_ terminatedProcess: Process) {
        guard process === terminatedProcess else { return }
        process = nil
        cleanupPipeHandlers()
        reportState(false)

        if terminatedProcess.terminationStatus == 0 {
            reportStatus("External display stopped")
        } else {
            reportStatus("External display helper exited with code \(terminatedProcess.terminationStatus)")
        }
    }

    private func stopLocked(waitForExit: Bool) {
        let currentProcess = process
        process = nil
        cleanupPipeHandlers()

        if currentProcess?.isRunning == true {
            currentProcess?.terminate()
            if waitForExit {
                currentProcess?.waitUntilExit()
            }
        }

        reportStatus("External display stopped")
        reportState(false)
    }

    private func handleOutput(_ data: Data, isError: Bool) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
        for line in lines {
            if let status = line.stripPrefix("status:") {
                reportStatus(status)
            } else if let input = line.stripPrefix("input:") {
                inputHandler?(input)
            } else if isError {
                reportStatus("External display error: \(line)")
            }
        }
    }

    private func cleanupPipeHandlers() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        errorPipe = nil
    }

    private func resolveHelperURL() -> URL? {
        let fileManager = FileManager.default
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        let bundled = executableDirectory?.appendingPathComponent("MtoGExternalDisplayWorker")
        if let bundled, fileManager.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let debug = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/MtoGExternalDisplayWorker")
        if fileManager.isExecutableFile(atPath: debug.path) {
            return debug
        }

        return nil
    }

    private func reportStatus(_ status: String) {
        statusHandler?(status)
    }

    private func reportState(_ running: Bool) {
        stateHandler?(running)
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
