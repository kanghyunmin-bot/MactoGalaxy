import Darwin
import Foundation
import MtoGCore
import MtoGMedia

final class ExternalDisplayWorker: @unchecked Sendable {
    private let videoPort: UInt16 = 46002
    private let inputPort: UInt16 = 46003
    private let width = 1920
    private let height = 1200
    private let framesPerSecond = 60
    private let runState = WorkerRunState()
    private var signalSource: DispatchSourceSignal?

    func run() -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        installSignalHandler()
        let adb = WorkerADBBridge(videoPort: videoPort, inputPort: inputPort)
        let backend = CGVirtualDisplayBackend()
        let touch = TouchInputServer(port: inputPort)
        let capture = ScreenCaptureSource()
        var sender: VideoStreamSender?
        var pump: EncodedFramePump?
        var encoder: VideoEncoderPipeline?

        do {
            workerStatus("Starting Galaxy external display receiver")
            try adb.startReceiver()
            workerStatus("Creating isolated Mac virtual monitor")
            let displayID = try backend.create()
            try touch.start(displayID: displayID)

            let receiverCapabilities = configuredReceiverCapabilities()
            let localCapabilities = CodecCapabilities(
                codecs: availableHardwareCodecs(),
                maxWidth: width,
                maxHeight: height,
                maxFramesPerSecond: framesPerSecond
            )
            var negotiated = try CodecNegotiator.negotiate(
                sender: localCapabilities,
                receiver: receiverCapabilities
            )
            let relay = EncoderOutputRelay()
            do {
                encoder = try makeEncoder(codec: negotiated.codec, relay: relay)
            } catch {
                guard negotiated.codec == .hevc,
                      localCapabilities.codecs.contains(.h264),
                      receiverCapabilities.codecs.contains(.h264) else { throw error }
                negotiated = try CodecNegotiator.negotiate(
                    sender: CodecCapabilities(
                        codecs: [.h264],
                        maxWidth: negotiated.width,
                        maxHeight: negotiated.height,
                        maxFramesPerSecond: negotiated.framesPerSecond
                    ),
                    receiver: receiverCapabilities
                )
                encoder = try makeEncoder(codec: .h264, relay: relay)
            }
            guard let encoder else { throw WorkerError.encodeFailed("encoder unavailable") }

            let streamSender = VideoStreamSender(
                port: videoPort,
                codec: negotiated.codec,
                width: negotiated.width,
                height: negotiated.height
            )
            sender = streamSender
            try streamSender.connect(timeoutSeconds: 6)
            let framePump = EncodedFramePump(sender: streamSender) { [runState] error in
                runState.fail(error)
            }
            pump = framePump
            relay.setHandler { result in framePump.submit(result) }

            try capture.start(
                displayID: displayID,
                width: negotiated.width,
                height: negotiated.height,
                framesPerSecond: negotiated.framesPerSecond
            )
            workerStatus(
                "Galaxy external display streaming \(negotiated.codec.rawValue) " +
                "\(negotiated.width)x\(negotiated.height) at target \(negotiated.framesPerSecond) fps"
            )
            while runState.isRunning {
                guard let frame = capture.queue.take(timeout: 0.1) else { continue }
                do {
                    try encoder.encode(frame)
                } catch {
                    runState.fail(error)
                }
            }
            if let failure = runState.failure { throw failure }
            shutdown(
                capture: capture,
                encoder: encoder,
                pump: framePump,
                sender: streamSender,
                touch: touch,
                backend: backend,
                adb: adb
            )
            return 0
        } catch {
            capture.stop()
            try? encoder?.complete()
            pump?.finish()
            encoder?.invalidate()
            sender?.close()
            touch.stop()
            backend.stop()
            adb.stop()
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            fputs("error:\(message)\n", stderr)
            return 2
        }
    }

    private func makeEncoder(codec: VideoCodec, relay: EncoderOutputRelay) throws -> VideoEncoderPipeline {
        try VideoEncoderPipeline(
            codec: codec,
            width: width,
            height: height,
            framesPerSecond: framesPerSecond
        ) { result in relay.submit(result) }
    }

    private func availableHardwareCodecs() -> [VideoCodec] {
        [.hevc, .h264].filter {
            VideoToolboxCodecSupport.hardwareStatus(for: $0, width: width, height: height) == .available
        }
    }

    private func configuredReceiverCapabilities() -> CodecCapabilities {
        let value = ProcessInfo.processInfo.environment["MTOG_RECEIVER_VIDEO_CODECS"] ?? "h264"
        let codecs = value.split(separator: ",").compactMap { VideoCodec(rawValue: String($0)) }
        return CodecCapabilities(
            codecs: codecs.isEmpty ? [.h264] : codecs,
            maxWidth: width,
            maxHeight: height,
            maxFramesPerSecond: framesPerSecond
        )
    }

    private func shutdown(
        capture: ScreenCaptureSource,
        encoder: VideoEncoderPipeline,
        pump: EncodedFramePump,
        sender: VideoStreamSender,
        touch: TouchInputServer,
        backend: CGVirtualDisplayBackend,
        adb: WorkerADBBridge
    ) {
        capture.stop()
        try? encoder.complete()
        pump.finish()
        encoder.invalidate()
        sender.close()
        touch.stop()
        backend.stop()
        adb.stop()
    }

    private func installSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global(qos: .userInitiated))
        source.setEventHandler { [runState] in runState.stop() }
        signalSource = source
        source.resume()
    }
}

final class EncoderOutputRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (Result<RealtimeEncodedFrame, Error>) -> Void)?

    func setHandler(_ handler: @escaping @Sendable (Result<RealtimeEncodedFrame, Error>) -> Void) {
        lock.lock(); self.handler = handler; lock.unlock()
    }

    func submit(_ result: Result<RealtimeEncodedFrame, Error>) {
        lock.lock(); let handler = handler; lock.unlock()
        handler?(result)
    }
}

private final class WorkerRunState: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private var storedFailure: Error?

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    var failure: Error? {
        lock.lock(); defer { lock.unlock() }
        return storedFailure
    }

    func stop() {
        lock.lock(); running = false; lock.unlock()
    }

    func fail(_ error: Error) {
        lock.lock()
        if storedFailure == nil { storedFailure = error }
        running = false
        lock.unlock()
    }
}
