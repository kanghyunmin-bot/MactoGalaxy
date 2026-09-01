import Darwin
import Foundation
import MtoGCore
import MtoGMedia

final class VideoStreamSender: @unchecked Sendable {
    private let port: UInt16
    private let codec: VideoCodec
    private let width: Int
    private let height: Int
    private let sessionID = UUID()
    private var sequence: UInt64 = 0
    private var socketFD: Int32 = -1
    private var sentConfig = false
    private let lock = NSLock()

    init(port: UInt16, codec: VideoCodec, width: Int, height: Int) {
        self.port = port
        self.codec = codec
        self.width = width
        self.height = height
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
        lock.lock(); defer { lock.unlock() }
        if socketFD >= 0 {
            Darwin.shutdown(socketFD, SHUT_RDWR)
            Darwin.close(socketFD)
            socketFD = -1
        }
    }

    private func sendPacket(kind: VideoPacketKind, flags: UInt8, timestamp: UInt64, payload: Data) throws {
        sequence += 1
        let packet = VideoPacket(
            kind: kind,
            codec: codec,
            flags: flags,
            sessionID: sessionID,
            sequence: sequence,
            presentationTimeUs: timestamp,
            width: width,
            height: height,
            payload: payload
        )
        try writeAll(VideoPacketCodec.encode(packet))
    }

    private func openSocket() throws -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw WorkerError.socketConnectFailed(String(cString: strerror(errno))) }
        var noSigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))
        var sendTimeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
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
