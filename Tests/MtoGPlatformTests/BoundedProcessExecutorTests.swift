import Foundation
import Testing
@testable import MtoGPlatform

struct BoundedProcessExecutorTests {
    @Test
    func capturesOutputAndStatus() throws {
        let result = try BoundedProcessExecutor.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf output; printf error >&2; exit 7"],
            timeout: 2
        )
        #expect(result.status == 7)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "output")
        #expect(String(decoding: result.stderr, as: UTF8.self) == "error")
    }

    @Test
    func terminatesAtDeadline() {
        #expect(throws: BoundedProcessError.self) {
            _ = try BoundedProcessExecutor.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["2"],
                timeout: 0.02
            )
        }
    }
}

struct ProcessRegressionTests {
    @Test func outputFloodIsBounded() {
        #expect(throws: BoundedProcessError.outputLimitExceeded(16384)) {
            _ = try BoundedProcessExecutor.run(executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "while :; do printf '12345678901234567890'; printf '12345678901234567890' >&2; done"],
                timeout: 2, maximumOutputBytes: 16384)
        }
    }
    @Test func inheritedPipeDoesNotReturnPartialSuccess() {
        let start = ProcessInfo.processInfo.systemUptime
        #expect(throws: BoundedProcessError.outputDrainTimedOut) {
            _ = try BoundedProcessExecutor.run(executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "sleep 1 & printf done"], timeout: 2, drainTimeout: 0.02)
        }
        #expect(ProcessInfo.processInfo.systemUptime - start < 0.8)
    }
    @Test func launchFailureAndRepeatedStop() throws {
        #expect(throws: (any Error).self) {
            _ = try BoundedProcessExecutor.run(executableURL: URL(fileURLWithPath: "/nonexistent/mtog"), arguments: [], timeout: 1)
        }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "trap '' TERM; while :; do :; done"]
        try p.run()
        Thread.sleep(forTimeInterval: 0.02)
        BoundedProcessExecutor.stop(p, timeout: 0.02)
        BoundedProcessExecutor.stop(p, timeout: 0.02)
        #expect(!p.isRunning)
    }
}
