import Darwin
import Foundation
import MtoGCore
import MtoGMedia

final class VideoStreamSender: @unchecked Sendable {
    private let port: UInt16
    private var codec: VideoCodec
    private var width: Int
    private var height: Int
    private let sessionID: UUID
    private var sequence: UInt64 = 0
    private var socketFD: Int32 = -1
    private var sentConfig = false
    private let lock = NSLock()
    private let controlStateLock = NSLock()
    private var controlThread: Thread?
    private var controlFinished: DispatchSemaphore?
    private var readingControls = false

    init(port: UInt16, codec: VideoCodec, width: Int, height: Int, sessionID: UUID) {
        self.port = port
        self.codec = codec
        self.width = width
        self.height = height
        self.sessionID = sessionID
    }

    func connect(timeoutSeconds: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var reason = "timeout"
        repeat {
            do {
                socketFD = try openSocket()
                return
            } catch {
                reason = error.localizedDescription
                Thread.sleep(forTimeInterval: 0.18)
            }
        } while Date() < deadline
        throw WorkerError.socketConnectFailed(reason)
    }

    func receiveCapabilities(timeoutSeconds: TimeInterval) throws -> CodecCapabilities {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var parser = BoundedVideoParser()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            if socketFD < 0 {
                do { socketFD = try openSocket() }
                catch { Thread.sleep(forTimeInterval: 0.18); continue }
            }
            let count = Darwin.recv(socketFD, &bytes, bytes.count, 0)
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) { continue }
            if count <= 0 {
                // ADB accepts the local connection before the Android listener is ready.
                // No video has been sent yet, so retry the handshake within the same deadline.
                Darwin.close(socketFD)
                socketFD = -1
                parser = BoundedVideoParser()
                Thread.sleep(forTimeInterval: 0.18)
                if Date() < deadline {
                    do { socketFD = try openSocket() } catch { continue }
                }
                continue
            }
            for packet in try parser.append(Data(bytes.prefix(count))) {
                guard packet.kind == .control,
                      packet.controlCode == .capabilities,
                      packet.sessionID == sessionID else { continue }
                return try decodeCapabilities(packet.payload)
            }
        }
        throw WorkerError.socketConnectFailed("receiver capabilities timed out")
    }

    func startControlReader(_ handler: @escaping @Sendable (VideoControlCode) -> Void) {
        controlStateLock.lock(); readingControls = true; controlStateLock.unlock()
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            defer { finished.signal() }
            self?.controlLoop(handler: handler)
        }
        controlFinished = finished
        controlThread = thread
        thread.start()
    }

    func update(codec: VideoCodec, width: Int, height: Int) {
        lock.lock(); defer { lock.unlock() }
        self.codec = codec
        self.width = width
        self.height = height
        sentConfig = false
    }

    func send(_ frame: RealtimeEncodedFrame) throws {
        lock.lock(); defer { lock.unlock() }
        if !sentConfig {
            guard let config = frame.config else { throw WorkerError.encodeFailed("codec config missing") }
            try sendPacket(kind: .config, flags: 0, timestamp: 0, payload: config)
            sentConfig = true
        }
        try sendPacket(
            kind: .accessUnit,
            flags: frame.accessUnit.isKeyframe ? VideoPacket.keyframeFlag : 0,
            timestamp: frame.accessUnit.presentationTimeUs,
            payload: frame.accessUnit.annexBData
        )
    }

    func close() {
        controlStateLock.lock(); readingControls = false; controlStateLock.unlock()
        lock.lock()
        if socketFD >= 0 {
            Darwin.shutdown(socketFD, SHUT_RDWR)
            Darwin.close(socketFD)
            socketFD = -1
        }
        lock.unlock()
        _ = controlFinished?.wait(timeout: .now() + 2)
        controlThread = nil
        controlFinished = nil
    }

    private var isReadingControls: Bool {
        controlStateLock.lock(); defer { controlStateLock.unlock() }
        return readingControls
    }

    private func controlLoop(handler: @escaping @Sendable (VideoControlCode) -> Void) {
        let parser = BoundedVideoParser()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while isReadingControls {
            let count = Darwin.recv(socketFD, &bytes, bytes.count, 0)
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) { continue }
            if count <= 0 { return }
            do {
                for packet in try parser.append(Data(bytes.prefix(count))) {
                    guard packet.kind == .control, packet.sessionID == sessionID else { continue }
                    handler(packet.controlCode)
                }
            } catch {
                return
            }
        }
    }

    private func sendPacket(kind: VideoPacketKind, flags: UInt8, timestamp: UInt64, payload: Data) throws {
        sequence += 1
        try writeAll(VideoPacketCodec.encode(VideoPacket(
            kind: kind,
            codec: codec,
            flags: flags,
            sessionID: sessionID,
            sequence: sequence,
            presentationTimeUs: timestamp,
            width: width,
            height: height,
            payload: payload
        )))
    }

    private func decodeCapabilities(_ payload: Data) throws -> CodecCapabilities {
        guard payload.count == 11 else { throw WorkerError.socketConnectFailed("invalid capability payload") }
        let mask = payload[0]
        var codecs: [VideoCodec] = []
        if mask & 2 != 0 { codecs.append(.hevc) }
        if mask & 1 != 0 { codecs.append(.h264) }
        let width = readUInt32(payload, 1)
        let height = readUInt32(payload, 5)
        let fps = Int(payload[9]) << 8 | Int(payload[10])
        return CodecCapabilities(codecs: codecs, maxWidth: width, maxHeight: height, maxFramesPerSecond: fps)
    }

    private func readUInt32(_ data: Data, _ offset: Int) -> Int {
        Int(data[offset]) << 24 | Int(data[offset + 1]) << 16 | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
    }

    private func openSocket() throws -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw WorkerError.socketConnectFailed(String(cString: strerror(errno))) }
        var noSigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            let reason = String(cString: strerror(errno))
            Darwin.close(fd)
            throw WorkerError.socketConnectFailed(reason)
        }
        return fd
    }

    private func writeAll(_ data: Data) throws {
        guard socketFD >= 0 else { throw WorkerError.streamDisconnected }
        let succeeded = data.withUnsafeBytes { bytes -> Bool in
            guard let base = bytes.baseAddress else { return true }
            var sent = 0
            while sent < data.count {
                let result = Darwin.send(socketFD, base.advanced(by: sent), data.count - sent, 0)
                if result < 0 && errno == EINTR { continue }
                if result <= 0 { return false }
                sent += result
            }
            return true
        }
        guard succeeded else { throw WorkerError.streamDisconnected }
    }
}
