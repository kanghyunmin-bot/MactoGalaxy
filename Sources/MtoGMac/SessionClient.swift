import Foundation
import MtoGCore
import Network

@MainActor
final class SessionClient: ObservableObject {
    enum State: Equatable {
        case idle
        case preparingBridge
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastReceivedMessage: SessionEnvelope?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var healthText = "연결 상태 확인 대기 중"
    @Published private(set) var activeTransportDescription = "활성 연결 없음"

    private let bridge: ADBBridge
    private let identity: SessionIdentitySnapshot
    private var connection: NWConnection?
    private var activeBonjourEndpoint: NWEndpoint?
    private var activeBonjourName = ""
    private var activeRoute: ConnectionRoute = .none
    private var connectionGeneration: UInt64 = 0
    private let queue = DispatchQueue(label: "com.mtog.session-client", qos: .userInitiated)
    private let frameParser = BoundedFrameParser()
    private let replayGuard = SessionReplayGuard()
    private var currentSessionId = UUID().uuidString
    private var currentSessionToken = UUID().uuidString
    private var localNonce = UUID().uuidString
    private var remoteNonce = ""
    private var outboundSequenceNo: UInt64 = 0
    private var shouldAutoReconnect = false
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var handshakeTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var lastInboundAt: Date?
    private let reconnectPolicy = ReconnectPolicy(
        maxAttempts: 8,
        baseDelaySeconds: 1,
        maximumDelaySeconds: 16
    )

    private enum HandshakePhase {
        case waitingAck
        case waitingConfirmation
        case complete
    }

    private var handshakePhase = HandshakePhase.waitingAck
    private var expectedConfirmMessageID: UUID?

    private enum ConnectionRoute: Equatable, Sendable {
        case none
        case adb
        case lan(host: String, port: UInt16)
        case bonjour(name: String)

        var wireName: String {
            switch self {
            case .none:
                return "none"
            case .adb:
                return "usb-adb-dev"
            case .lan:
                return "secure-lan-dev"
            case .bonjour:
                return "secure-lan-mdns-dev"
            }
        }

        var description: String {
            switch self {
            case .none:
                return "활성 연결 없음"
            case .adb:
                return "USB 개발 모드"
            case .lan(let host, let port):
                return "Wi-Fi \(host):\(port)"
            case .bonjour(let name):
                return "Wi-Fi \(name)"
            }
        }
    }

    init(
        bridge: ADBBridge = ADBBridge(),
        identity: SessionIdentitySnapshot
    ) {
        self.bridge = bridge
        self.identity = identity
    }

    private func beginProtocolSession() {
        currentSessionId = UUID().uuidString
        currentSessionToken = UUID().uuidString
        localNonce = UUID().uuidString
        remoteNonce = ""
        handshakePhase = .waitingAck
        expectedConfirmMessageID = nil
        outboundSequenceNo = 0
        frameParser.reset()
        replayGuard.reset()
    }

    var activeSessionGeneration: UInt64 {
        connectionGeneration
    }

    var selectedDeviceSerial: String? {
        bridge.selectedDeviceSerial
    }

    var activeProtocolSessionID: UUID? {
        state == .connected ? UUID(uuidString: currentSessionId) : nil
    }

    var hasActiveADBSession: Bool {
        state == .connected && activeRoute == .adb
    }

    func connectOverADB() async {
        await connectOverADBInternal(isReconnectAttempt: false)
    }

    func connectOverLAN(host rawHost: String, port: UInt16 = 46001) async {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            markFailed("갤럭시 IP를 입력하세요")
            return
        }
        await connectOverLANInternal(host: host, port: port, isReconnectAttempt: false)
    }

    func connectOverBonjour(endpoint: NWEndpoint, displayName: String) async {
        await connectOverBonjourInternal(endpoint: endpoint, displayName: displayName, isReconnectAttempt: false)
    }

    private func connectOverADBInternal(isReconnectAttempt: Bool) async {
        if !isReconnectAttempt {
            shouldAutoReconnect = true
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = 0
        }
        stopHeartbeat()
        stopHandshake()
        connection?.cancel()
        connection = nil
        activeBonjourEndpoint = nil
        activeBonjourName = ""
        connectionGeneration += 1
        state = .preparingBridge
        activeRoute = .adb
        activeTransportDescription = activeRoute.description
        lastErrorMessage = nil
        lastReceivedMessage = nil
        lastInboundAt = nil
        frameParser.reset()
        healthText = isReconnectAttempt
            ? "재연결 \(reconnectAttempt)회차: USB 연결 준비 중"
            : "USB 연결 준비 중"

        do {
            try bridge.prepare()
            state = .connecting
            healthText = "USB 터널을 여는 중"

            let connection = NWConnection(
                host: "127.0.0.1",
                port: NWEndpoint.Port(rawValue: bridge.configuration.hostPort)!,
                using: .tcp
            )
            self.connection = connection
            let generation = connectionGeneration
            beginProtocolSession()

            connection.stateUpdateHandler = { [weak self] newState in
                Task { @MainActor in
                    self?.handle(state: newState, generation: generation)
                }
            }
            connection.start(queue: queue)
            receiveLoop(generation: generation)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            markFailed(message)
        }
    }

    private func connectOverLANInternal(host: String, port: UInt16, isReconnectAttempt: Bool) async {
        if !isReconnectAttempt {
            shouldAutoReconnect = true
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = 0
        }
        stopHeartbeat()
        stopHandshake()
        connection?.cancel()
        connection = nil
        activeBonjourEndpoint = nil
        activeBonjourName = ""
        connectionGeneration += 1
        state = .connecting
        activeRoute = .lan(host: host, port: port)
        activeTransportDescription = activeRoute.description
        lastErrorMessage = nil
        lastReceivedMessage = nil
        lastInboundAt = nil
        frameParser.reset()
        healthText = isReconnectAttempt
            ? "재연결 \(reconnectAttempt)회차: Wi-Fi 연결 여는 중"
            : "Wi-Fi 연결 여는 중"

        do {
            healthText = "갤럭시 Wi-Fi 수신 상태 확인 중"
            try waitForLANPort(host: host, port: port, timeoutSeconds: 5)
        } catch {
            healthText = "Wi-Fi 수신 상태를 확인하지 못했지만 직접 연결을 시도합니다"
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        self.connection = connection
        let generation = connectionGeneration
        beginProtocolSession()

        connection.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                self?.handle(state: newState, generation: generation)
            }
        }
        connection.start(queue: queue)
        receiveLoop(generation: generation)
    }

    private func connectOverBonjourInternal(endpoint: NWEndpoint, displayName: String, isReconnectAttempt: Bool) async {
        if !isReconnectAttempt {
            shouldAutoReconnect = true
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = 0
        }
        stopHeartbeat()
        stopHandshake()
        connection?.cancel()
        connection = nil
        connectionGeneration += 1
        state = .connecting
        activeRoute = .bonjour(name: displayName)
        activeBonjourEndpoint = endpoint
        activeBonjourName = displayName
        activeTransportDescription = activeRoute.description
        lastErrorMessage = nil
        lastReceivedMessage = nil
        lastInboundAt = nil
        frameParser.reset()
        healthText = isReconnectAttempt
            ? "재연결 \(reconnectAttempt)회차: 찾은 기기에 Wi-Fi 연결 중"
            : "찾은 기기에 Wi-Fi 연결 중"

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection
        let generation = connectionGeneration
        beginProtocolSession()

        connection.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                self?.handle(state: newState, generation: generation)
            }
        }
        connection.start(queue: queue)
        receiveLoop(generation: generation)
    }

    private func waitForLANPort(host: String, port: UInt16, timeoutSeconds: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        repeat {
            if tcpPortAcceptsConnections(host: host, port: port) {
                return
            }
            try? awaitSleep(milliseconds: 250)
        } while Date() < deadline
    }

    private func tcpPortAcceptsConnections(host: String, port: UInt16) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedConnectionProbe()
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                result.markReady()
                semaphore.signal()
            case .failed, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 0.4)
        connection.cancel()
        return result.isReady
    }

    private func awaitSleep(milliseconds: UInt64) throws {
        Thread.sleep(forTimeInterval: Double(milliseconds) / 1000.0)
    }

    func disconnect() {
        shouldAutoReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        stopHeartbeat()
        stopHandshake()
        let routeBeforeDisconnect = activeRoute
        connectionGeneration += 1
        connection?.cancel()
        connection = nil
        activeBonjourEndpoint = nil
        activeBonjourName = ""
        activeRoute = .none
        activeTransportDescription = activeRoute.description
        state = .idle
        healthText = "사용자가 연결을 해제했습니다"
        if routeBeforeDisconnect == .adb {
            try? bridge.clearForward()
        }
    }

    func sendPing() async {
        await send(makeEnvelope(type: .ping, payload: ["kind": "adb-mvp"]))
    }

    func sendHello(expectedGeneration: UInt64? = nil) async {
        if let expectedGeneration, expectedGeneration != connectionGeneration { return }
        await send(
            makeEnvelope(
                type: .hello,
                payload: [
                    "role": "mac-controller",
                    "protocolVersion": String(ProtocolLimits.version),
                    "sessionToken": currentSessionToken,
                    "clientNonce": localNonce,
                    "transport": activeRoute.wireName,
                    "transportCandidates": "usb-adb-dev,usb-aoa-candidate,secure-lan-candidate",
                    "clipboardKinds": "text,image,video,file",
                    "frameProtection": "session-sequence-replay-guard",
                    "encryptedAppSession": "not-enabled-in-dev-build",
                    "publicKey": identity.publicKeyBase64
                ]
            ),
            allowsHandshake: true
        )
    }

    func sendPairRequest(code: String) async {
        await send(
            makeEnvelope(
                type: .pairRequest,
                payload: [
                    "code": code,
                    "publicKey": identity.publicKeyBase64
                ],
                requiresAck: true
            )
        )
    }

    func sendClipboardPreview(text: String, kind: String) async {
        await send(
            makeEnvelope(
                type: .clipboardPreview,
                payload: [
                    "kind": kind,
                    "text": text
                ]
            )
        )
    }

    func sendClipboardPreview(payload: [String: String], expectedGeneration: UInt64) async {
        guard expectedGeneration == connectionGeneration else { return }
        await send(
            makeEnvelope(
                type: .clipboardPreview,
                payload: payload
            )
        )
    }

    private func send(_ message: SessionEnvelope, allowsHandshake: Bool = false) async {
        guard let connection else { return }
        let generation = connectionGeneration
        guard message.sessionId == currentSessionId else { return }
        guard allowsHandshake || (state == .connected && handshakePhase == .complete) else { return }

        do {
            let data = try ControlFrameCodec.encode(message)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
            }
        } catch {
            guard generation == connectionGeneration, self.connection === connection else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            markFailed(message)
        }
    }

    private func makeEnvelope(
        type: SessionMessageType,
        payload: [String: String] = [:],
        requiresAck: Bool = false
    ) -> SessionEnvelope {
        outboundSequenceNo += 1
        var boundPayload = payload
        boundPayload["sessionToken"] = currentSessionToken
        boundPayload["clientNonce"] = localNonce
        if !remoteNonce.isEmpty {
            boundPayload["serverNonce"] = remoteNonce
        }
        return SessionEnvelope(
            sessionId: currentSessionId,
            sequenceNo: outboundSequenceNo,
            requiresAck: requiresAck,
            type: type,
            deviceId: identity.deviceId,
            deviceName: identity.deviceName,
            payload: boundPayload
        )
    }

    private func handle(state newState: NWConnection.State, generation: UInt64) {
        guard generation == connectionGeneration else { return }

        switch newState {
        case .ready:
            state = .connecting
            activeTransportDescription = activeRoute.description
            healthText = "\(activeRoute.description) protocol v2 확인 중"
            startHandshakeTimeout(generation: generation)
            Task {
                await sendHello(expectedGeneration: generation)
            }
        case .failed(let error):
            markFailed(error.localizedDescription)
        case .cancelled:
            stopHeartbeat()
            if case .failed = state { return }
            if shouldAutoReconnect {
                markFailed("USB 터널이 취소되었습니다")
            } else {
                state = .idle
                healthText = "연결 해제됨"
            }
        default:
            break
        }
    }

    private func receiveLoop(generation: UInt64) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            Task { @MainActor in
                guard generation == self.connectionGeneration else { return }

                if let error {
                    self.markFailed(error.localizedDescription)
                    return
                }

                if let data, !data.isEmpty {
                    do {
                        let frames = try self.frameParser.append(data)
                        try self.consume(frames: frames, generation: generation)
                    } catch {
                        self.connection?.cancel()
                        self.markFailed(self.protocolErrorMessage(error))
                        return
                    }
                }

                if isComplete {
                    do {
                        try self.frameParser.finish()
                    } catch {
                        self.markFailed(self.protocolErrorMessage(error))
                        return
                    }
                    if self.shouldAutoReconnect {
                        self.markFailed("USB 터널이 닫혔습니다")
                    } else {
                        self.state = .idle
                        self.healthText = "연결이 닫혔습니다"
                    }
                    return
                }

                self.receiveLoop(generation: generation)
            }
        }
    }

    private func consume(frames: [ControlFrame], generation: UInt64) throws {
        for frame in frames {
            let message = try ControlFrameCodec.decode(frame)
            let token = message.payload["sessionToken"] ?? ""
            let clientNonce = message.payload["clientNonce"] ?? ""
            let serverNonce = message.payload["serverNonce"] ?? ""

            switch handshakePhase {
            case .waitingAck:
                guard message.type == .helloAck,
                      message.sessionId == currentSessionId,
                      token == currentSessionToken,
                      message.payload["protocolVersion"] == String(ProtocolLimits.version),
                      clientNonce == localNonce,
                      !serverNonce.isEmpty else {
                    throw ControlProtocolError.invalidJSON
                }
                remoteNonce = serverNonce
                replayGuard.begin(
                    sessionID: currentSessionId,
                    token: currentSessionToken,
                    clientNonce: localNonce,
                    serverNonce: remoteNonce,
                    generation: generation
                )
            case .waitingConfirmation:
                guard message.type == .helloConfirmed || message.type == .error,
                      !remoteNonce.isEmpty,
                      clientNonce == localNonce,
                      serverNonce == remoteNonce else {
                    throw ControlProtocolError.invalidJSON
                }
                if message.type == .helloConfirmed {
                    guard message.payload["protocolVersion"] == String(ProtocolLimits.version),
                          message.payload["replyTo"] == expectedConfirmMessageID?.uuidString else {
                        throw ControlProtocolError.invalidJSON
                    }
                }
            case .complete:
                guard message.type != .helloAck,
                      message.type != .helloConfirm,
                      message.type != .helloConfirmed,
                      !remoteNonce.isEmpty,
                      clientNonce == localNonce,
                      serverNonce == remoteNonce else {
                    throw ControlProtocolError.invalidJSON
                }
            }

            guard replayGuard.accept(
                sessionID: message.sessionId,
                token: token,
                clientNonce: clientNonce,
                serverNonce: serverNonce,
                sequence: message.sequenceNo,
                generation: generation
            ) else {
                lastErrorMessage = "오래되었거나 다른 세션의 메시지를 무시했습니다"
                continue
            }
            lastReceivedMessage = message
            lastInboundAt = Date()

            if message.type == .helloAck {
                let confirmation = makeEnvelope(type: .helloConfirm)
                expectedConfirmMessageID = confirmation.id
                handshakePhase = .waitingConfirmation
                Task { await self.send(confirmation, allowsHandshake: true) }
            } else if message.type == .helloConfirmed {
                handshakePhase = .complete
                stopHandshake()
                state = .connected
                reconnectAttempt = 0
                reconnectTask?.cancel()
                reconnectTask = nil
                healthText = "\(activeRoute.description)로 연결됨"
                startHeartbeat()
            } else if message.type == .ping {
                let pong = makeEnvelope(type: .pong, payload: ["replyTo": message.id.uuidString])
                Task { await self.send(pong) }
            } else if message.type == .pong {
                healthText = "상태 확인 정상 \(Self.timeLabel(Date()))"
            } else if message.type == .error {
                let reason = message.payload["reason"] ?? message.payload["code"] ?? "상대 기기에서 오류를 보냈습니다"
                lastErrorMessage = reason
                healthText = "상대 기기 오류: \(reason)"
            }
        }
    }

    private func protocolErrorMessage(_ error: Error) -> String {
        if case ControlProtocolError.unsupportedVersion(let version) = error {
            return "프로토콜 버전이 맞지 않습니다: \(version)"
        }
        return "protocol v2 메시지를 처리하지 못했습니다"
    }

    private func markFailed(_ message: String) {
        stopHeartbeat()
        stopHandshake()
        state = .failed(message)
        lastErrorMessage = message
        healthText = "연결 문제: \(message)"
        scheduleReconnect(reason: message)
    }

    private func startHandshakeTimeout(generation: UInt64) {
        stopHandshake()
        handshakeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      generation == self.connectionGeneration,
                      self.state == .connecting else { return }
                self.markFailed("protocol v2 응답 시간이 초과되었습니다")
            }
        }
    }

    private func stopHandshake() {
        handshakeTask?.cancel()
        handshakeTask = nil
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        let generation = connectionGeneration
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self,
                          self.state == .connected,
                          self.connectionGeneration == generation else { return }
                    self.healthText = "상태 확인 보냄 \(Self.timeLabel(Date()))"
                    let ping = self.makeEnvelope(
                        type: .ping,
                        payload: [
                            "kind": "heartbeat",
                            "sentAtUnixMs": String(Int64(Date().timeIntervalSince1970 * 1000))
                        ]
                    )
                    Task { await self.send(ping) }
                }
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func scheduleReconnect(reason: String) {
        guard shouldAutoReconnect else { return }
        guard reconnectTask == nil else { return }

        reconnectTask = Task { [weak self] in
            while !Task.isCancelled {
                let attempt = await MainActor.run { () -> Int in
                    guard let self else { return Int.max }
                    self.reconnectAttempt += 1
                    return self.reconnectAttempt
                }
                let delaySeconds = await MainActor.run {
                    self?.reconnectPolicy.delaySeconds(forAttempt: attempt)
                }
                guard let delaySeconds else {
                    await MainActor.run {
                        self?.healthText = "반복 실패로 자동 재연결을 중지했습니다"
                    }
                    return
                }
                let maxAttempts = await MainActor.run { self?.reconnectPolicy.maxAttempts ?? 0 }
                await MainActor.run {
                    self?.healthText = "\(delaySeconds)초 후 재연결 \(attempt)/\(maxAttempts): \(reason)"
                }
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
                guard !Task.isCancelled else { return }

                let route = await MainActor.run { self?.activeRoute ?? .none }
                switch route {
                case .adb:
                    await self?.connectOverADBInternal(isReconnectAttempt: true)
                case .lan(let host, let port):
                    await self?.connectOverLANInternal(host: host, port: port, isReconnectAttempt: true)
                case .bonjour:
                    guard let endpoint = await MainActor.run(body: { self?.activeBonjourEndpoint }),
                          let displayName = await MainActor.run(body: { self?.activeBonjourName }),
                          !displayName.isEmpty else {
                        return
                    }
                    await self?.connectOverBonjourInternal(
                        endpoint: endpoint,
                        displayName: displayName,
                        isReconnectAttempt: true
                    )
                case .none:
                    return
                }
                try? await Task.sleep(nanoseconds: 6_000_000_000)

                let connected = await MainActor.run { self?.state == .connected }
                if connected {
                    return
                }
            }
        }
    }

    private static func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private final class LockedConnectionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var ready = false

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ready
    }

    func markReady() {
        lock.lock()
        ready = true
        lock.unlock()
    }
}
