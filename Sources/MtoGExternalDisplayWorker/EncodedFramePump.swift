import Foundation
import MtoGMedia

final class EncodedFramePump: @unchecked Sendable {
    private let sender: VideoStreamSender
    private let failureHandler: @Sendable (Error) -> Void
    private let queue = DispatchQueue(label: "com.mtog.video-output", qos: .userInteractive)
    private let lock = NSLock()
    private var buffer = LatestEncodedFrameBuffer()
    private var drainScheduled = false

    var droppedFrames: Int {
        lock.lock(); defer { lock.unlock() }
        return buffer.droppedFrames
    }

    init(sender: VideoStreamSender, failureHandler: @escaping @Sendable (Error) -> Void) {
        self.sender = sender
        self.failureHandler = failureHandler
    }

    func submit(_ result: Result<RealtimeEncodedFrame, Error>) {
        switch result {
        case .failure(let error):
            failureHandler(error)
        case .success(let frame):
            lock.lock()
            buffer.offer(frame)
            let shouldSchedule = !drainScheduled
            drainScheduled = true
            lock.unlock()
            if shouldSchedule {
                queue.async { [weak self] in self?.drain() }
            }
        }
    }

    func finish() {
        queue.sync {}
    }

    private func drain() {
        while true {
            lock.lock()
            guard let frame = buffer.take() else {
                drainScheduled = false
                lock.unlock()
                return
            }
            lock.unlock()
            do {
                try sender.send(frame)
            } catch {
                failureHandler(error)
                lock.lock()
                drainScheduled = false
                lock.unlock()
                return
            }
        }
    }
}
