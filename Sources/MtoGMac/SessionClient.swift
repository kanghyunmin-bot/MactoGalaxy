import Foundation
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
    @Published private(set) var healthText = "Heartbeat idle"
    @Published private(set) var activeTransportDescription = "No active transport"

    private let bridge: ADBBridge
    private let identity: SessionIdentitySnapshot
    private var connection: NWConnection?
    private var activeRoute: ConnectionRoute = .none
    private var connectionGeneration: UInt64 = 0
    private let queue = DispatchQueue(label: "com.mtog.session-client", qos: .userInitiated)
    private var receiveBuffer = Data()
    private let replayGuard = SessionReplayGuard()
    private var currentSessionId = UUID().uuidString
    private var outboundSequenceNo: UInt64 = 0
    private var shouldAutoReconnect = false
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var lastInboundAt: Date?
    private let maxReceiveBufferBytes = 36 * 1_024 * 1_024
    private let maxOutboundFrameBytes = 36 * 1_024 * 1_024
    private let maxReconnectAttempts = 8

    private enum ConnectionRoute: Equatable, Sendable {
        case none
        case adb
        case lan(host: String, port: UInt16)

        var wireName: String {
            switch self {
            case .none:
                return "none"
            case .adb:
                return "usb-adb-dev"
            case .lan:
                return "secure-lan-dev"
            }
        }

        var description: String {
            switch self {
            case .none:
                return "No active transport"
            case .adb:
                return "USB ADB Dev Mode"
            case .lan(let host, let port):
                return "Wireless LAN \(host):\(port)"
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

    func connectOverADB() async {
        await connectOverADBInternal(isReconnectAttempt: false)
    }

    func connectOverLAN(host rawHost: String, port: UInt16 = 46001) async {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            markFailed("Wireless host is empty")
            return
        }
        await connectOverLANInternal(host: host, port: port, isReconnectAttempt: false)
    }

    private func connectOverADBInternal(isReconnectAttempt: Bool) async {
        if !isReconnectAttempt {
            shouldAutoReconnect = true
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempt = 0
        }
        stopHeartbeat()
        connection?.cancel()
        connection = nil
        connectionGeneration += 1
        state = .preparingBridge
        activeRoute = .adb
        activeTransportDescription = activeRoute.description
        lastErrorMessage = nil
        lastReceivedMessage = nil
        lastInboundAt = nil
        receiveBuffer.removeAll(keepingCapacity: false)
        healthText = isReconnectAttempt
            ? "Reconnect attempt \(reconnectAttempt) preparing ADB bridge"
            : "Preparing ADB bridge"

        do {
            try bridge.prepare()
            state = .connecting
            healthText = "Opening localhost ADB tunnel"

            let connection = NWConnection(
                host: "127.0.0.1",
                port: NWEndpoint.Port(rawValue: bridge.configuration.hostPort)!,
                using: .tcp
            )
            self.connection = connection
            let generation = connectionGeneration
            currentSessionId = UUID().uuidString
            outboundSequenceNo = 0
            replayGuard.reset()

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
        connection?.cancel()
        connection = nil
        connectionGeneration += 1
        state = .connecting
        activeRoute = .lan(host: host, port: port)
        activeTransportDescription = activeRoute.description
        lastErrorMessage = nil
        lastReceivedMessage = nil
        lastInboundAt = nil
        receiveBuffer.removeAll(keepingCapacity: false)
        healthText = isReconnectAttempt
            ? "Reconnect attempt \(reconnectAttempt) opening wireless LAN session"
            : "Opening wireless LAN session"

        let adbSerial = "\(host):5555"
        do {
            healthText = "Preparing Galaxy app over wireless ADB"
            _ = try bridge.connectWirelessADB(host: host)
            try bridge.startCompanionApp(serial: adbSerial)
            healthText = "Opening wireless LAN session"
            try waitForLANPort(host: host, port: port, timeoutSeconds: 5)
        } catch {
            healthText = "Wireless app bootstrap failed; trying direct socket"
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        self.connection = connection
        let generation = connectionGeneration
        currentSessionId = UUID().uuidString
        outboundSequenceNo = 0
        replayGuard.reset()

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
        let routeBeforeDisconnect = activeRoute
        connectionGeneration += 1
        connection?.cancel()
        connection = nil
        activeRoute = .none
        activeTransportDescription = activeRoute.description
        state = .idle
        healthText = "Disconnected by user"
        if routeBeforeDisconnect == .adb {
            try? bridge.clearForward()
        }
    }

    func sendPing() async {
        await send(makeEnvelope(type: .ping, payload: ["kind": "adb-mvp"]))
    }

    func sendHello() async {
        await send(
            makeEnvelope(
                type: .hello,
                payload: [
                    "role": "mac-controller",
                    "transport": activeRoute.wireName,
                    "transportCandidates": "usb-adb-dev,usb-aoa-candidate,secure-lan-candidate",
                    "clipboardKinds": "text,image,video,file",
                    "frameProtection": "session-sequence-replay-guard",
                    "encryptedAppSession": "not-enabled-in-dev-build",
                    "publicKey": identity.publicKeyBase64
                ]
            )
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

    func sendClipboardPreview(payload: [String: String]) async {
        await send(
            makeEnvelope(
                type: .clipboardPreview,
                payload: payload
            )
        )
    }

    func sendEnterControlMode(edge: String) async {
        await send(
            makeEnvelope(
                type: .enterControlMode,
                payload: ["edge": edge]
            )
        )
    }

    func sendExitControlMode(reason: String) async {
        await send(
            makeEnvelope(
                type: .exitControlMode,
                payload: ["reason": reason]
            )
        )
    }

    func sendRemoteTap(normalizedX: Double, normalizedY: Double) async {
        await send(
            makeEnvelope(
                type: .remoteTap,
                payload: [
                    "normalizedX": String(format: "%.4f", normalizedX),
                    "normalizedY": String(format: "%.4f", normalizedY)
                ]
            )
        )
    }

    func sendRemoteGesture(
        kind: String,
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double,
        durationMs: Int
    ) async {
        await send(
            makeEnvelope(
                type: .remoteGesture,
                payload: [
                    "kind": kind,
                    "startX": String(format: "%.4f", startX),
                    "startY": String(format: "%.4f", startY),
                    "endX": String(format: "%.4f", endX),
                    "endY": String(format: "%.4f", endY),
                    "durationMs": String(durationMs)
                ]
            )
        )
    }

    func sendRemotePinch(
        centerX: Double,
        centerY: Double,
        magnification: Double
    ) async {
        await send(
            makeEnvelope(
                type: .remotePinch,
                payload: [
                    "centerX": String(format: "%.4f", centerX),
                    "centerY": String(format: "%.4f", centerY),
                    "magnification": String(format: "%.4f", magnification)
                ]
            )
        )
    }

    func sendRemoteTouchStart(normalizedX: Double, normalizedY: Double) async {
        await send(
            makeEnvelope(
                type: .remoteTouchStart,
                payload: [
                    "normalizedX": String(format: "%.4f", normalizedX),
                    "normalizedY": String(format: "%.4f", normalizedY)
                ]
            )
        )
    }

    func sendRemoteTouchMove(normalizedX: Double, normalizedY: Double) async {
        await send(
            makeEnvelope(
                type: .remoteTouchMove,
                payload: [
                    "normalizedX": String(format: "%.4f", normalizedX),
                    "normalizedY": String(format: "%.4f", normalizedY)
                ]
            )
        )
    }

    func sendRemoteTouchEnd(normalizedX: Double, normalizedY: Double) async {
        await send(
            makeEnvelope(
                type: .remoteTouchEnd,
                payload: [
                    "normalizedX": String(format: "%.4f", normalizedX),
                    "normalizedY": String(format: "%.4f", normalizedY)
                ]
            )
        )
    }

    func sendRemoteBack() async {
        await send(makeEnvelope(type: .remoteBack))
    }

    func sendRemoteHome() async {
        await send(makeEnvelope(type: .remoteHome))
    }

    func sendRemotePointerUpdate(
        normalizedX: Double,
        normalizedY: Double,
        primaryButtonDown: Bool
    ) async {
        await send(
            makeEnvelope(
                type: .remotePointerUpdate,
                payload: [
                    "normalizedX": String(format: "%.4f", normalizedX),
                    "normalizedY": String(format: "%.4f", normalizedY),
                    "primaryButtonDown": primaryButtonDown ? "true" : "false"
                ]
            )
        )
    }

    func sendRemoteText(_ text: String) async {
        await send(
            makeEnvelope(
                type: .remoteText,
                payload: ["text": text]
            )
        )
    }

    func sendRemoteDeleteBackward() async {
        await send(makeEnvelope(type: .remoteDeleteBackward))
    }

    func sendRemoteEnterKey() async {
        await send(makeEnvelope(type: .remoteEnterKey))
    }

    private func send(_ message: SessionEnvelope) async {
        guard let connection else { return }

        do {
            let data = try SessionCodec.encodeLine(message)
            guard data.count <= maxOutboundFrameBytes else {
                lastErrorMessage = "Frame too large for MVP transport"
                return
            }
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
        return SessionEnvelope(
            sessionId: currentSessionId,
            sequenceNo: outboundSequenceNo,
            requiresAck: requiresAck,
            type: type,
            deviceId: identity.deviceId,
            deviceName: identity.deviceName,
            payload: payload
        )
    }

    private func handle(state newState: NWConnection.State, generation: UInt64) {
        guard generation == connectionGeneration else { return }

        switch newState {
        case .ready:
            state = .connected
            reconnectAttempt = 0
            reconnectTask?.cancel()
            reconnectTask = nil
            activeTransportDescription = activeRoute.description
            healthText = "Connected over \(activeRoute.description). Heartbeat active."
            startHeartbeat()
            Task {
                await sendHello()
            }
        case .failed(let error):
            markFailed(error.localizedDescription)
        case .cancelled:
            stopHeartbeat()
            if shouldAutoReconnect {
                markFailed("ADB tunnel cancelled")
            } else {
                state = .idle
                healthText = "Disconnected"
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
                    self.receiveBuffer.append(data)
                    if self.receiveBuffer.count > self.maxReceiveBufferBytes {
                        self.receiveBuffer.removeAll(keepingCapacity: false)
                        self.connection?.cancel()
                        self.markFailed("Inbound frame too large for MVP transport")
                        return
                    }
                    self.consumeBufferedMessages()
                }

                if isComplete {
                    if self.shouldAutoReconnect {
                        self.markFailed("ADB tunnel closed")
                    } else {
                        self.state = .idle
                        self.healthText = "Connection closed"
                    }
                    return
                }

                self.receiveLoop(generation: generation)
            }
        }
    }

    private func consumeBufferedMessages() {
        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            let chunk = receiveBuffer.prefix(upTo: newline)
            receiveBuffer.removeSubrange(...newline)

            guard !chunk.isEmpty else { continue }

            do {
                let message = try SessionCodec.decodeLine(Data(chunk))
                guard replayGuard.accept(message) else {
                    lastErrorMessage = "Ignored stale or replayed frame for session \(message.sessionId)"
                    continue
                }
                lastReceivedMessage = message
                lastInboundAt = Date()

                if message.type == .ping {
                    Task {
                        await self.send(self.makeEnvelope(type: .pong, payload: ["replyTo": message.id.uuidString]))
                    }
                } else if message.type == .pong {
                    healthText = "Heartbeat ok \(Self.timeLabel(Date()))"
                } else if message.type == .error {
                    let reason = message.payload["reason"] ?? message.payload["code"] ?? "Peer reported an error"
                    lastErrorMessage = reason
                    healthText = "Peer error: \(reason)"
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func markFailed(_ message: String) {
        stopHeartbeat()
        state = .failed(message)
        lastErrorMessage = message
        healthText = "Connection issue: \(message)"
        scheduleReconnect(reason: message)
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.state == .connected else { return }
                    self.healthText = "Heartbeat sent \(Self.timeLabel(Date()))"
                    Task {
                        await self.send(
                            self.makeEnvelope(
                                type: .ping,
                                payload: [
                                    "kind": "heartbeat",
                                    "sentAtUnixMs": String(Int64(Date().timeIntervalSince1970 * 1000))
                                ]
                            )
                        )
                    }
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
                let maxAttempts = await MainActor.run { self?.maxReconnectAttempts ?? 0 }
                guard attempt <= maxAttempts else {
                    await MainActor.run {
                        self?.healthText = "Auto reconnect stopped after repeated failures"
                    }
                    return
                }

                let delaySeconds = min(2 + attempt, 10)
                await MainActor.run {
                    self?.healthText = "Reconnect \(attempt)/\(maxAttempts) in \(delaySeconds)s: \(reason)"
                }
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
                guard !Task.isCancelled else { return }

                let route = await MainActor.run { self?.activeRoute ?? .none }
                switch route {
                case .adb:
                    await self?.connectOverADBInternal(isReconnectAttempt: true)
                case .lan(let host, let port):
                    await self?.connectOverLANInternal(host: host, port: port, isReconnectAttempt: true)
                case .none:
                    return
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)

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
