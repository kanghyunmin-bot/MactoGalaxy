import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

struct CapturedVideoFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let presentationTimeUs: UInt64
}

final class LatestCapturedFrameQueue: @unchecked Sendable {
    private let condition = NSCondition()
    private var latest: CapturedVideoFrame?
    private var stopped = false
    private var storedFailure: Error?

    var failure: Error? {
        condition.lock(); defer { condition.unlock() }
        return storedFailure
    }
    private(set) var droppedFrames = 0

    func offer(_ frame: CapturedVideoFrame) {
        condition.lock()
        guard !stopped else { condition.unlock(); return }
        if latest != nil { droppedFrames += 1 }
        latest = frame
        condition.signal()
        condition.unlock()
    }

    func take(timeout: TimeInterval) -> CapturedVideoFrame? {
        condition.lock()
        defer { condition.unlock() }
        if latest == nil && !stopped {
            _ = condition.wait(until: Date().addingTimeInterval(timeout))
        }
        let frame = latest
        latest = nil
        return frame
    }

    func stop(error: Error? = nil) {
        condition.lock()
        storedFailure = error
        stopped = true
        latest = nil
        condition.broadcast()
        condition.unlock()
    }
}

final class ScreenCaptureSource: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = LatestCapturedFrameQueue()
    private let callbackQueue = DispatchQueue(label: "com.mtog.capture-callback", qos: .userInteractive)
    private let session = CaptureSessionState()

    func start(displayID: CGDirectDisplayID, width: Int, height: Int, framesPerSecond: Int) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedResult()
        let task = Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw WorkerError.captureFailed("virtual display not found")
                }
                try Task.checkCancellation()
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.width = width
                configuration.height = height
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
                configuration.queueDepth = 3
                configuration.pixelFormat = kCVPixelFormatType_32BGRA
                configuration.showsCursor = true
                configuration.capturesAudio = false
                let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: callbackQueue)
                try await stream.startCapture()
                guard session.adopt(stream) else {
                    try? await stream.stopCapture()
                    throw CancellationError()
                }
                result.set(.success(()))
            } catch {
                result.set(.failure(error))
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 15) == .success else {
            task.cancel()
            stop()
            throw WorkerError.captureFailed("화면 기록 시작 시간 초과 · macOS 권한을 확인하세요")
        }
        try result.get().get()
    }

    func stop() {
        queue.stop()
        guard let stream = session.close() else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            try? await stream.stopCapture()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.stop(error: error)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMTimeConvertScale(
            CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            timescale: 1_000_000,
            method: .default
        ).value
        queue.offer(CapturedVideoFrame(pixelBuffer: pixelBuffer, presentationTimeUs: UInt64(max(time, 0))))
    }
}

private final class LockedResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Result<Void, Error>?

    func set(_ value: Result<Void, Error>) {
        lock.lock(); self.value = value; lock.unlock()
    }

    func get() -> Result<Void, Error> {
        lock.lock(); defer { lock.unlock() }
        return value ?? .failure(WorkerError.captureFailed("capture did not return a result"))
    }
}

/// A timed-out start must never install a capture stream after cleanup has returned.
private final class CaptureSessionState: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var stream: SCStream?

    func adopt(_ stream: SCStream) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return false }
        self.stream = stream
        return true
    }

    func close() -> SCStream? {
        lock.lock(); defer { lock.unlock() }
        closed = true
        let value = stream
        stream = nil
        return value
    }
}
