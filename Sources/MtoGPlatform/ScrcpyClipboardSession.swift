import CryptoKit
import Darwin
import Foundation
import MtoGCore

public struct ScrcpyClipboardConfiguration: Sendable {
    public static let serverSHA256 = "8588238c9a5a00aa542906b6ec7e6d5541d9ffb9b5d0f6e1bc0e365e2303079e"
    var expectedSHA256 = Self.serverSHA256
    public let adbURL: URL
    public let serverURL: URL
    public init(adbURL: URL, serverURL: URL) { self.adbURL = adbURL; self.serverURL = serverURL }
}

enum ScrcpySessionUpdate: Sendable { case ready, text(String), failed, permissionUnconfirmed }

/// One worker owns the process, socket and forwarding lease. stop only sets cancellation;
/// cleanup finishes before run returns, and all callbacks remain generation-bound by its owner.
final class ScrcpyClipboardSession: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var outgoing: Data?
    func stop() { lock.lock(); cancelled = true; outgoing = nil; lock.unlock() }
    func send(_ bytes: Data) { lock.lock(); if !cancelled { outgoing = bytes }; lock.unlock() }
    private var stopped: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    private func takeOutgoing() -> Data? { lock.lock(); defer { lock.unlock() }; defer { outgoing = nil }; return outgoing }

    func run(configuration: ScrcpyClipboardConfiguration, serial: String,
             update: @escaping @Sendable (ScrcpySessionUpdate) -> Void) {
        let scid = String(format: "%08x", UInt32.random(in: 1...0x7fffffff))
        let remote = "/data/local/tmp/mtog-clipboard-\(scid).jar"
        var port: String?
        var fd: Int32 = -1
        let process = Process()
        func adb(_ args: [String]) throws -> String {
            let result = try BoundedProcessExecutor.run(executableURL: configuration.adbURL,
                arguments: ["-s", serial] + args, timeout: 5)
            guard result.status == 0 else { throw ScrcpyProtocolError.invalidMessage }
            return String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        defer {
            if fd >= 0 { Darwin.close(fd) }
            BoundedProcessExecutor.stop(process, timeout: 0.2)
            if let port { _ = try? adb(["forward", "--remove", "tcp:\(port)"]) }
            _ = try? adb(["shell", "rm", "-f", remote])
        }
        do {
            guard !stopped else { return }
            _ = try adb(["push", configuration.serverURL.path, remote])
            guard !stopped else { return }
            let value = try adb(["forward", "tcp:0", "localabstract:scrcpy_\(scid)"])
            guard let number = UInt16(value), number > 0 else { throw ScrcpyProtocolError.invalidMessage }
            port = value
            guard !stopped else { return }
            process.executableURL = configuration.adbURL
            process.arguments = ["-s", serial, "shell", "CLASSPATH=\(remote)", "app_process", "/",
                "com.genymobile.scrcpy.Server", "3.3.4", "scid=\(scid)", "video=false", "audio=false",
                "control=true", "tunnel_forward=true", "send_dummy_byte=true", "send_device_meta=false",
                "clipboard_autosync=false", "power_on=false", "cleanup=true"]
            // Never persist arbitrary server diagnostics or clipboard contents.
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            while !stopped && ProcessInfo.processInfo.systemUptime < deadline {
                fd = socket(AF_INET, SOCK_STREAM, 0)
                guard fd >= 0 else { throw ScrcpyProtocolError.invalidMessage }
                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = number.bigEndian
                address.sin_addr.s_addr = inet_addr("127.0.0.1")
                let connected = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                }
                if connected == 0 {
                    _ = fcntl(fd, F_SETFL, O_NONBLOCK)
                    // ADB accepts the local forward even before Android listens. Its dummy byte,
                    // not connect(), establishes the remote control socket. Retry an early EOF.
                    var dummy: UInt8 = 255
                    var verified = false
                    while !stopped && ProcessInfo.processInfo.systemUptime < deadline {
                        let count = Darwin.recv(fd, &dummy, 1, 0)
                        if count == 1 {
                            guard dummy == 0 else { throw ScrcpyProtocolError.invalidMessage }
                            verified = true; break
                        }
                        if count == 0 { break }
                        if errno != EAGAIN && errno != EINTR { break }
                        usleep(10_000)
                    }
                    if verified { break }
                }
                Darwin.close(fd); fd = -1; usleep(50_000)
            }
            guard !stopped else { return }
            guard fd >= 0 else { throw ScrcpyProtocolError.invalidMessage }
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var parser = ScrcpyClipboardParser()
            var pending = Data()
            var sendDeadline = ProcessInfo.processInfo.systemUptime + 2
            var nextPoll = 0.0
            var lastResponse = ProcessInfo.processInfo.systemUptime
            var reportedUnavailable = false
            var ready = false
            var bytes = [UInt8](repeating: 0, count: 8192)
            while !stopped {
                guard process.isRunning else { throw ScrcpyProtocolError.invalidMessage }
                let now = ProcessInfo.processInfo.systemUptime
                if pending.isEmpty {
                    if let outgoing = takeOutgoing() { pending = outgoing; nextPoll = 0 }
                    else if now >= nextPoll { pending = ScrcpyClipboardCodec.getClipboard; nextPoll = now + 0.5 }
                    sendDeadline = now + 2
                }
                if !pending.isEmpty {
                    let sent = pending.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
                    if sent > 0 { pending = Data(pending.dropFirst(sent)) }
                    else if errno != EAGAIN && errno != EINTR { throw ScrcpyProtocolError.invalidMessage }
                    if now > sendDeadline { throw ScrcpyProtocolError.invalidMessage }
                }
                let count = Darwin.recv(fd, &bytes, bytes.count, 0)
                if count == 0 { throw ScrcpyProtocolError.invalidMessage }
                if count > 0 {
                    for message in try parser.append(Data(bytes.prefix(count))) {
                        if case .clipboard(let text) = message {
                            lastResponse = now; reportedUnavailable = false
                            if !ready { ready = true; update(.ready) }
                            update(.text(text))
                        }
                        // ACK means processed, not successful clipboard write (upstream sends ACK on failure).
                    }
                } else if errno != EAGAIN && errno != EINTR { throw ScrcpyProtocolError.invalidMessage }
                if now - lastResponse > 3 && !reportedUnavailable {
                    ready = false; reportedUnavailable = true; update(.permissionUnconfirmed)
                }
                usleep(10_000)
            }
        } catch { if !stopped { update(.failed) } }
    }
}

@MainActor
public protocol ClipboardSessionTransport: ClipboardEventTransport {
    var statusHandler: ((ClipboardAuthorityStatus) -> Void)? { get set }
    func start(configuration: ScrcpyClipboardConfiguration, serial: String, sessionID: String, trusted: Bool)
}

@MainActor
public final class ShellClipboardTransport: ClipboardSessionTransport {
    public private(set) var status: ClipboardAuthorityStatus = .stopped
    public var receiveHandler: ((ClipboardEvent) -> Void)?
    public var statusHandler: ((ClipboardAuthorityStatus) -> Void)?
    private var eventTask: Task<Void, Never>?
    private var generation = UUID()
    private var worker: ScrcpyClipboardSession?
    private var sessionID = ""
    private var sequence: UInt64 = 0
    private var lastContent: String?
    private var pendingLocal: String?
    private var pendingSince = 0.0
    private var highestSent: UInt64 = 0
    public init() {}

    public func start(configuration: ScrcpyClipboardConfiguration, serial: String, sessionID: String, trusted: Bool) {
        stop()
        guard trusted, !serial.isEmpty, UUID(uuidString: sessionID) != nil else {
            setStatus(.blocked("신뢰된 USB 세션이 필요합니다")); return
        }
        guard let size = try? configuration.serverURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 2_097_152,
              let data = try? Data(contentsOf: configuration.serverURL),
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == configuration.expectedSHA256 else {
            setStatus(.unsupported("scrcpy-server 3.3.4 파일 없음 또는 버전/hash 불일치")); return
        }
        self.sessionID = sessionID
        sequence = 0; highestSent = 0; lastContent = nil; pendingLocal = nil
        let generation = self.generation
        let worker = ScrcpyClipboardSession()
        self.worker = worker
        setStatus(.negotiating)
        let stream = AsyncStream<ScrcpySessionUpdate>.makeStream(bufferingPolicy: .bufferingNewest(8))
        eventTask = Task { [weak self] in
            for await update in stream.stream {
                guard let self, self.generation == generation else { return }
                self.handle(update)
            }
        }
        Task.detached {
            worker.run(configuration: configuration, serial: serial) { update in
                stream.continuation.yield(update)
            }
            stream.continuation.finish()
        }
    }
    private func handle(_ update: ScrcpySessionUpdate) {
        guard worker != nil else { return }
        switch update {
        case .ready: setStatus(.available)
        case .permissionUnconfirmed: setStatus(.permissionRequired("응답 없음: 잠금·권한·빈 클립보드 확인 필요"))
        case .failed: worker?.stop(); worker = nil; setStatus(.failed("scrcpy control 연결 종료 또는 프로토콜 오류 · 다시 활성화하세요"))
        case .text(let text):
            if let pendingLocal {
                if pendingLocal == text { self.pendingLocal = nil; lastContent = text; return }
                if ProcessInfo.processInfo.systemUptime - pendingSince < 2 { return }
                self.pendingLocal = nil
                worker?.stop(); worker = nil
                setStatus(.failed("클립보드 쓰기 확인 실패: 잠금·권한 또는 동시 변경 확인 필요"))
                return
            }
            guard text != lastContent else { return }
            lastContent = text
            sequence += 1
            guard let event = try? ClipboardEvent.make(sourceID: "scrcpy-device", sessionID: sessionID,
                sequence: sequence, kind: text.hasPrefix("https://") || text.hasPrefix("http://") ? .url : .text, content: text) else { return }
            receiveHandler?(event)
        }
    }
    public func send(_ event: ClipboardEvent) {
        switch status {
        case .available, .negotiating, .permissionRequired: break
        default: return
        }
        guard event.sessionID == sessionID,
              event.contentHash == ClipboardEvent.hash(event.content), event.sequence > highestSent else { return }
        do {
            let bytes = try ScrcpyClipboardCodec.setClipboard(event.content, sequence: event.sequence)
            highestSent = event.sequence
            pendingLocal = event.content; pendingSince = ProcessInfo.processInfo.systemUptime
            worker?.send(bytes)
        } catch { setStatus(.failed("텍스트가 scrcpy 전송 상한 262130 bytes를 초과했습니다")) }
    }
    public func stop() {
        generation = UUID(); eventTask?.cancel(); eventTask = nil; worker?.stop(); worker = nil
        receiveHandler = nil; pendingLocal = nil; lastContent = nil
        setStatus(.stopped)
    }
    private func setStatus(_ value: ClipboardAuthorityStatus) { status = value; statusHandler?(value) }
}
