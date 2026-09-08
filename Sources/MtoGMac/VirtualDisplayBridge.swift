import MtoGPlatform
import Foundation
import MtoGCore

final class VirtualDisplayBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.mtog.virtual-display-supervisor", qos: .userInitiated)
    private let requestLock = NSLock()
    private var requestGeneration: UInt64 = 0
    private let adbBridge: ADBBridge
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var generation: UInt64 = 0
    private var activeSerial: String?
    private var activeSession: UUID?
    private var activeRequest: UInt64 = 0
    private var lastWorkerError: String?
    private var lines = [BoundedLineBuffer(), BoundedLineBuffer()]

    init(adbBridge: ADBBridge) {
        self.adbBridge = adbBridge
    }

    var statusHandler: ((String) -> Void)?
    var stateHandler: ((Bool) -> Void)?
    var inputHandler: ((String, UUID, UInt64) -> Void)?

    func start(serial: String, sessionID: UUID, highQuality: Bool = true) {
        let request = nextRequestGeneration()
        queue.async { [weak self] in
            guard let self, self.isRequestActive(request) else { return }
            if self.process != nil {
                self.reportStatus("외장 디스플레이 도우미가 이미 실행 중입니다")
                self.reportState(true)
                return
            }

            guard let helperURL = self.resolveHelperURL() else {
                self.reportStatus("외장 디스플레이 시작 실패: 도우미 실행 파일이 없습니다")
                self.reportState(false)
                return
            }

            self.lastWorkerError = nil
            self.generation += 1
            let generation = self.generation
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = helperURL
            process.arguments = ["--serial", serial, "--session", sessionID.uuidString]
            process.arguments! += ["--width", highQuality ? "2560" : "1920", "--height", highQuality ? "1600" : "1200"]
            process.standardOutput = stdout
            process.standardError = stderr

            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                self?.queue.async { [weak self] in
                    self?.handleOutput(data, isError: false, generation: generation)
                }
            }
            stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                self?.queue.async { [weak self] in
                    self?.handleOutput(data, isError: true, generation: generation)
                }
            }

            process.terminationHandler = { [weak self] terminatedProcess in
                guard let bridge = self else { return }
                bridge.queue.async { [weak bridge] in
                    bridge?.handleTermination(terminatedProcess, generation: generation)
                }
            }

            do {
                try process.run()
                guard self.isRequestActive(request) else {
                    BoundedProcessExecutor.stop(process, timeout: 2)
                    return
                }
                self.process = process
                self.activeSerial = serial
                self.activeSession = sessionID
                self.activeRequest = request
                self.outputPipe = stdout
                self.errorPipe = stderr
                self.reportState(true)
                self.reportStatus("외장 디스플레이 도우미 시작됨")
            } catch {
                self.cleanupPipeHandlers()
                self.reportState(false)
                self.reportStatus("외장 디스플레이 시작 실패: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        invalidateRequests()
        queue.async { [weak self] in
            guard let self else { return }
            self.stopLocked(waitForExit: false)
        }
    }

    func stopImmediately() {
        invalidateRequests()
        queue.sync {
            stopLocked(waitForExit: true)
        }
    }

    private func handleTermination(_ terminatedProcess: Process, generation: UInt64) {
        guard process === terminatedProcess, generation == self.generation else { return }
        requestLock.lock()
        if requestGeneration == activeRequest { requestGeneration += 1 }
        requestLock.unlock()
        process = nil
        let serial = activeSerial
        activeSerial = nil
        cleanupPipeHandlers()
        if let serial { adbBridge.clearExternalDisplayMappings(serial: serial) }
        reportState(false)

        if terminatedProcess.terminationStatus == 0 {
            reportStatus("외장 디스플레이가 종료되었습니다")
        } else {
            reportStatus(lastWorkerError ?? "외장 디스플레이 도우미가 종료되었습니다. 종료 코드: \(terminatedProcess.terminationStatus)")
        }
    }

    private func stopLocked(waitForExit: Bool) {
        guard let currentProcess = process else {
            reportState(false)
            return
        }
        if waitForExit {
            BoundedProcessExecutor.stop(currentProcess, timeout: 2)
        } else {
            BoundedProcessExecutor.stop(currentProcess, timeout: 2)
        }
        generation += 1
        process = nil
        let serial = activeSerial
        activeSerial = nil
        cleanupPipeHandlers()
        if let serial { adbBridge.clearExternalDisplayMappings(serial: serial) }

        reportStatus("외장 디스플레이가 종료되었습니다")
        reportState(false)
    }

    private func handleOutput(_ data: Data, isError: Bool, generation: UInt64) {
        guard generation == self.generation, !data.isEmpty else { return }
        guard let lines = try? self.lines[isError ? 1 : 0].append(data) else {
            reportStatus("외장 디스플레이 출력 프로토콜 오류")
            stopLocked(waitForExit: false)
            return
        }
        for line in lines {
            if let status = line.stripPrefix("status:") {
                reportStatus(status)
            } else if let input = line.stripPrefix("input:") {
                if let session = activeSession { inputHandler?(input, session, activeRequest) }
            } else if isError {
                lastWorkerError = "외장 디스플레이 오류: \(line)"
                reportStatus(lastWorkerError!)
            }
        }
    }

    private func cleanupPipeHandlers() {
        activeSession = nil
        lines = [BoundedLineBuffer(), BoundedLineBuffer()]
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

    private func nextRequestGeneration() -> UInt64 {
        requestLock.lock(); defer { requestLock.unlock() }
        requestGeneration += 1
        return requestGeneration
    }

    private func invalidateRequests() {
        requestLock.lock(); requestGeneration += 1; requestLock.unlock()
    }

    func isRequestActive(_ request: UInt64) -> Bool {
        requestLock.lock(); defer { requestLock.unlock() }
        return request == requestGeneration
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
