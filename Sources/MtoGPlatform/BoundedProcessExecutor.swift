import Darwin
import Foundation

public enum BoundedProcessError: Error, LocalizedError, Equatable {
    case timedOut(TimeInterval)
    case outputLimitExceeded(Int)
    case outputDrainTimedOut
    public var errorDescription: String? {
        switch self {
        case .timedOut: return "Process execution deadline exceeded"
        case .outputLimitExceeded: return "Process output limit exceeded"
        case .outputDrainTimedOut: return "Process exited with inherited output pipes still open"
        }
    }
}

public struct BoundedProcessResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data
}

/// Infrastructure only: no reader tasks survive this synchronous, bounded call.
public enum BoundedProcessExecutor {
    public static func run(executableURL: URL, arguments: [String],
                           environment: [String: String]? = nil, timeout: TimeInterval,
                           maximumOutputBytes: Int = 1_048_576,
                           drainTimeout: TimeInterval = 0.2) throws -> BoundedProcessResult {
        let process = Process()
        let pipes = [Pipe(), Pipe()]
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = pipes[0]
        process.standardError = pipes[1]
        defer {
            for pipe in pipes {
                try? pipe.fileHandleForReading.close()
                try? pipe.fileHandleForWriting.close()
            }
        }
        try process.run()
        for pipe in pipes {
            try? pipe.fileHandleForWriting.close()
            let fd = pipe.fileHandleForReading.fileDescriptor
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        }
        defer { stop(process, timeout: 0.2) }
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        var exitDeadline: Double?
        var data = [Data(), Data()]
        var eof = [false, false]
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            for i in 0..<2 where !eof[i] {
                // One bounded read per stream per iteration prevents a noisy stream starving the deadline.
                let count = Darwin.read(pipes[i].fileHandleForReading.fileDescriptor, &buffer, buffer.count)
                if count > 0 {
                    guard data[0].count + data[1].count + count <= maximumOutputBytes else {
                        throw BoundedProcessError.outputLimitExceeded(maximumOutputBytes)
                    }
                    data[i].append(contentsOf: buffer.prefix(count))
                } else if count == 0 { eof[i] = true }
                else if errno != EAGAIN && errno != EINTR { throw BoundedProcessError.outputDrainTimedOut }
            }
            let now = ProcessInfo.processInfo.systemUptime
            if !process.isRunning {
                if eof.allSatisfy({ $0 }) {
                    return .init(status: process.terminationStatus, stdout: data[0], stderr: data[1])
                }
                if exitDeadline == nil { exitDeadline = now + max(0, drainTimeout) }
                if now >= exitDeadline! { throw BoundedProcessError.outputDrainTimedOut }
            } else if now >= deadline { throw BoundedProcessError.timedOut(timeout) }
            usleep(1_000)
        }
    }

    /// Preserve the owner's termination handler. Foundation owns and reaps the child.
    public static func stop(_ process: Process, timeout: TimeInterval) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(1_000) }
        if process.isRunning {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
            let killDeadline = ProcessInfo.processInfo.systemUptime + 0.5
            while process.isRunning && ProcessInfo.processInfo.systemUptime < killDeadline { usleep(1_000) }
        }
    }
}
