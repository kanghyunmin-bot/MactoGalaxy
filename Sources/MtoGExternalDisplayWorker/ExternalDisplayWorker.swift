import Darwin
import Foundation
import MtoGCore
import MtoGMedia

final class ExternalDisplayWorker: @unchecked Sendable {
    private let videoPort: UInt16 = 46002
    private let inputPort: UInt16 = 46003
    private let width: Int
    private let height: Int
    private let preferredCodec: VideoCodec?
    private let framesPerSecond = 60
    private let selectedSerial: String
    private let controlSessionID: UUID
    private let runState = WorkerRunState()
    private var signalSource: DispatchSourceSignal?

    init(selectedSerial: String, controlSessionID: UUID, width: Int = 1920, height: Int = 1200, preferredCodec: VideoCodec? = nil) {
        self.width = width
        self.height = height
        self.preferredCodec = preferredCodec
        self.selectedSerial = selectedSerial
        self.controlSessionID = controlSessionID
    }

    func run() -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        installSignalHandler()
        let adb = WorkerADBBridge(
            videoPort: videoPort,
            inputPort: inputPort,
            serial: selectedSerial,
            controlSessionID: controlSessionID
        )
        let backend = CGVirtualDisplayBackend()
        let touch = TouchInputServer(port: inputPort, controlSessionID: controlSessionID)
        let capture = ScreenCaptureSource()
        var sender: VideoStreamSender?
        var pump: EncodedFramePump?
        var encoder: VideoEncoderPipeline?

        do {
            workerStatus("Starting Galaxy external display receiver")
            try adb.startReceiver()
            workerStatus("Creating isolated Mac virtual monitor")
            let displayID = try backend.create(width: width, height: height)
            try touch.start(displayID: displayID)

            let streamSender = VideoStreamSender(
                port: videoPort,
                codec: .h264,
                width: width,
                height: height,
                sessionID: controlSessionID
            )
            sender = streamSender
            try streamSender.connect(timeoutSeconds: 6)
            let receiverCapabilities = try streamSender.receiveCapabilities(timeoutSeconds: 5)
            let localCapabilities = CodecCapabilities(
                codecs: availableHardwareCodecs(),
                maxWidth: width,
                maxHeight: height,
                maxFramesPerSecond: framesPerSecond
            )
            var negotiated = try CodecNegotiator.negotiate(sender: localCapabilities, receiver: receiverCapabilities)
            streamSender.update(
                codec: negotiated.codec,
                width: negotiated.width,
                height: negotiated.height
            )

            let relay = EncoderOutputRelay()
            let framePump = EncodedFramePump(sender: streamSender) { [runState] error in runState.fail(error) }
            pump = framePump
            relay.setHandler { result in framePump.submit(result) }
            do {
                encoder = try makeEncoder(codec: negotiated.codec, negotiated: negotiated, relay: relay)
            } catch {
                guard negotiated.codec == .hevc,
                      localCapabilities.codecs.contains(.h264),
                      receiverCapabilities.codecs.contains(.h264) else { throw error }
                negotiated = try h264Negotiation(local: localCapabilities, receiver: receiverCapabilities)
                streamSender.update(codec: .h264, width: negotiated.width, height: negotiated.height)
                encoder = try makeEncoder(codec: .h264, negotiated: negotiated, relay: relay)
            }
            guard var activeEncoder = encoder else { throw WorkerError.encodeFailed("encoder unavailable") }

            streamSender.startControlReader { [runState] code in
                switch code {
                case .requestKeyframe: runState.requestKeyframe()
                case .fallbackH264: runState.requestH264Fallback()
                default: break
                }
            }
            try capture.start(
                displayID: displayID,
                width: negotiated.width,
                height: negotiated.height,
                framesPerSecond: negotiated.framesPerSecond
            )
            reportStreaming(negotiated)

            while runState.isRunning {
                if runState.takeFallbackRequest(), negotiated.codec == .hevc {
                    try activeEncoder.complete()
                    framePump.finish()
                    activeEncoder.invalidate()
                    negotiated = try h264Negotiation(local: localCapabilities, receiver: receiverCapabilities)
                    streamSender.update(codec: .h264, width: negotiated.width, height: negotiated.height)
                    activeEncoder = try makeEncoder(codec: .h264, negotiated: negotiated, relay: relay)
                    encoder = activeEncoder
                    reportStreaming(negotiated)
                }
                if runState.takeKeyframeRequest() || framePump.needsKeyframe { activeEncoder.requestKeyframe() }
                guard let frame = capture.queue.take(timeout: 0.1) else {
                    if let error = capture.queue.failure { throw error }
                    continue
                }
                do { try activeEncoder.encode(frame) } catch { runState.fail(error) }
            }
            if let failure = runState.failure { throw failure }
            shutdown(
                capture: capture,
                encoder: activeEncoder,
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

    private func makeEncoder(
        codec: VideoCodec,
        negotiated: NegotiatedCodec,
        relay: EncoderOutputRelay
    ) throws -> VideoEncoderPipeline {
        try VideoEncoderPipeline(
            codec: codec,
            width: negotiated.width,
            height: negotiated.height,
            framesPerSecond: negotiated.framesPerSecond
        ) { result in relay.submit(result) }
    }

    private func availableHardwareCodecs() -> [VideoCodec] {
        (preferredCodec.map { [$0] } ?? [.hevc, .h264]).filter {
            VideoToolboxCodecSupport.hardwareStatus(for: $0, width: width, height: height) == .available
        }
    }

    private func h264Negotiation(
        local: CodecCapabilities,
        receiver: CodecCapabilities
    ) throws -> NegotiatedCodec {
        try CodecNegotiator.negotiate(
            sender: CodecCapabilities(
                codecs: local.codecs.contains(.h264) ? [.h264] : [],
                maxWidth: local.maxWidth,
                maxHeight: local.maxHeight,
                maxFramesPerSecond: local.maxFramesPerSecond
            ),
            receiver: receiver
        )
    }

    private func reportStreaming(_ negotiated: NegotiatedCodec) {
        workerStatus(
            "Mac capture/encoder ready; Galaxy rendered output unconfirmed: \(negotiated.codec.rawValue) " +
            "\(negotiated.width)x\(negotiated.height) at target \(negotiated.framesPerSecond) fps"
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
    private var keyframeRequested = false
    private var fallbackRequested = false
    private var fallbackUsed = false

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

    func requestKeyframe() {
        lock.lock(); keyframeRequested = true; lock.unlock()
    }

    func takeKeyframeRequest() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let value = keyframeRequested
        keyframeRequested = false
        return value
    }

    func requestH264Fallback() {
        lock.lock()
        if !fallbackUsed {
            fallbackRequested = true
            fallbackUsed = true
        }
        lock.unlock()
    }

    func takeFallbackRequest() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let value = fallbackRequested
        fallbackRequested = false
        return value
    }
}
