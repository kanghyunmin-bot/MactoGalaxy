import ApplicationServices
import Foundation

final class AoaHidBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.mtog.aoa-hid-bridge", qos: .userInitiated)
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    var statusHandler: ((String) -> Void)?
    var stateHandler: ((Bool) -> Void)?

    var isRunning: Bool {
        queue.sync {
            process?.isRunning == true && inputHandle != nil
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.process?.isRunning == true {
                self.reportStatus("AOA HID bridge already running")
                self.reportState(true)
                return
            }

            guard let helperURL = self.resolveHelperURL() else {
                self.reportStatus("AOA HID helper not found. Build with ./scripts/build-aoa-hid-probe.sh")
                self.reportState(false)
                return
            }

            let process = Process()
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = helperURL
            process.arguments = ["--stdio"]
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.handleOutputData(handle.availableData, isError: false)
            }
            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                self?.handleOutputData(handle.availableData, isError: true)
            }

            process.terminationHandler = { [weak self] _ in
                guard let bridge = self else { return }
                bridge.queue.async {
                    bridge.inputHandle = nil
                    bridge.process = nil
                    bridge.outputPipe?.fileHandleForReading.readabilityHandler = nil
                    bridge.errorPipe?.fileHandleForReading.readabilityHandler = nil
                    bridge.reportStatus("AOA HID bridge stopped")
                    bridge.reportState(false)
                }
            }

            do {
                try process.run()
                self.process = process
                self.inputHandle = inputPipe.fileHandleForWriting
                self.outputPipe = outputPipe
                self.errorPipe = errorPipe
                self.reportStatus("Starting AOA HID bridge")
                self.reportState(true)
            } catch {
                self.reportStatus("AOA HID bridge failed to start: \(error.localizedDescription)")
                self.reportState(false)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.writeLineLocked("quit")
            self.process?.terminate()
            self.inputHandle = nil
            self.process = nil
            self.reportState(false)
        }
    }

    func sendMouse(buttons: Int, dx: Int, dy: Int, wheel: Int = 0) {
        queue.async { [weak self] in
            self?.writeLineLocked("mouse \(buttons) \(dx) \(dy) \(wheel)")
        }
    }

    func sendKey(modifiers: Int, usage: Int) {
        queue.async { [weak self] in
            self?.writeLineLocked("key \(modifiers) \(usage)")
        }
    }

    func sendPinch(centerX: Int, centerY: Int, delta: Int, steps: Int = 8) {
        queue.async { [weak self] in
            self?.writeLineLocked("pinch \(centerX) \(centerY) \(delta) \(steps)")
        }
    }

    private func writeLineLocked(_ line: String) {
        guard let inputHandle, process?.isRunning == true else { return }
        guard let data = "\(line)\n".data(using: .utf8) else { return }
        do {
            try inputHandle.write(contentsOf: data)
        } catch {
            reportStatus("AOA HID write failed: \(error.localizedDescription)")
        }
    }

    private func handleOutputData(_ data: Data, isError: Bool) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let lastLine = lines.last else { return }
        reportStatus(isError ? "AOA HID error: \(lastLine)" : lastLine)
    }

    private func reportStatus(_ status: String) {
        statusHandler?(status)
    }

    private func reportState(_ running: Bool) {
        stateHandler?(running)
    }

    private func resolveHelperURL() -> URL? {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["MTOG_AOA_HID_HELPER"],
           fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        let bundleHelper = Bundle.main.resourceURL?.appendingPathComponent("aoa-hid-probe")
        if let bundleHelper, fileManager.isExecutableFile(atPath: bundleHelper.path) {
            return bundleHelper
        }

        let bundleURL = Bundle.main.bundleURL
        let repoFromDist = bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repoHelper = repoFromDist.appendingPathComponent(".build/tools/aoa-hid-probe")
        if fileManager.isExecutableFile(atPath: repoHelper.path) {
            return repoHelper
        }

        let cwdHelper = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent(".build/tools/aoa-hid-probe")
        if fileManager.isExecutableFile(atPath: cwdHelper.path) {
            return cwdHelper
        }

        return nil
    }
}
