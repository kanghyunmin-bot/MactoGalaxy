import AppKit
import ApplicationServices
import Combine
import Foundation
import MtoGCore

@MainActor
final class AppModel: ObservableObject {
    @Published var deviceName = Host.current().localizedName ?? "Mac"
    @Published var targetName = "Galaxy Tab"
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var transportStatus: TransportStatus = .usbWaiting
    @Published var wirelessHost: String = UserDefaults.standard.string(forKey: "com.mtog.wireless-host") ?? "" {
        didSet {
            UserDefaults.standard.set(wirelessHost, forKey: "com.mtog.wireless-host")
        }
    }
    @Published private(set) var wirelessDiscoveryStatus = "Wi-Fi 검색 대기 중"
    @Published private(set) var discoveredWirelessPeers: [WirelessDiscoveredPeer] = []
    @Published private(set) var screenRecordingAllowed = false
    @Published private(set) var touchInputAllowed = false
    @Published var highQualityDisplay = true
    @Published var usbCableLabel = "케이블 규격·연결 속도 미확인"
    @Published var trustState = TrustState(
        isTrusted: false,
        lastPairedDescription: "아직 저장된 기기가 없습니다",
        lastSeenDescription: "연결 기록 없음"
    )
    @Published var pairingCode = ["", "", "", ""]
    @Published var clipboardHistory: [ClipboardHistoryItem]
    @Published var isClipboardHistoryVisible = false
    @Published private(set) var clipboardSyncStatus = "클립보드 동기화 대기 중"
    @Published private(set) var automaticClipboardStatus = "자동 텍스트 클립보드 중지됨"
    @Published private(set) var automaticClipboardEnabled = false
    @Published private(set) var clipboardAuthority: ClipboardAuthorityStatus = .stopped
    @Published private(set) var pairingStatusText = "갤럭시 앱에 표시된 4자리 코드를 이 Mac에 입력하세요"
    @Published private(set) var trustedPeerCount = 0
    @Published private(set) var controlStatusText = "원격 조작 대기 중"
    @Published private(set) var externalDisplayStatusText = "외장 디스플레이 대기 중"
    @Published private(set) var isExternalDisplayRunning = false

    let transportCoordinator = TransportCoordinator()
    let sessionClient: SessionClient
    let virtualDisplayBridge: VirtualDisplayBridge
    let externalDisplayInputSynthesizer: ExternalDisplayInputSynthesizer
    let wirelessDiscoveryBrowser: WirelessDiscoveryBrowser
    let localIdentity: SessionIdentitySnapshot

    private let adbBridge: ADBBridge
    private let trustedPeerStore: TrustedPeerStore
    private let clipboardSyncController: ClipboardSyncController
    private let clipboardCoordinator: ClipboardCoordinator
    private var validatedPeerSession: UUID?
    private let clipboardHistoryPersistence: ClipboardHistoryPersistence
    private var cancellables: Set<AnyCancellable> = []

    init(identity: SessionIdentitySnapshot) {
        self.adbBridge = ADBBridge()
        self.trustedPeerStore = TrustedPeerStore()
        self.localIdentity = identity
        self.sessionClient = SessionClient(bridge: adbBridge, identity: localIdentity)
        self.clipboardSyncController = ClipboardSyncController()
        self.clipboardCoordinator = ClipboardCoordinator(sourceID: ClipboardSyncPayload.localSourceId)
        self.clipboardHistoryPersistence = ClipboardHistoryPersistence()
        self.virtualDisplayBridge = VirtualDisplayBridge(adbBridge: adbBridge)
        self.externalDisplayInputSynthesizer = ExternalDisplayInputSynthesizer()
        self.wirelessDiscoveryBrowser = WirelessDiscoveryBrowser()
        self.clipboardHistory = clipboardHistoryPersistence.load() ?? []
        virtualDisplayBridge.statusHandler = { [weak self] status in
            Task { @MainActor in
                self?.externalDisplayStatusText = status
            }
        }
        virtualDisplayBridge.stateHandler = { [weak self] running in
            Task { @MainActor in
                self?.isExternalDisplayRunning = running
                if !running { self?.externalDisplayInputSynthesizer.releaseAll() }
                if running {
                    self?.transportStatus = .adbMvp
                }
            }
        }
        virtualDisplayBridge.inputHandler = { [weak self] payload, sessionID, request in
            Task { @MainActor in
                guard let self,
                      self.trustState.isTrusted,
                      self.sessionClient.hasActiveADBSession,
                      self.sessionClient.activeProtocolSessionID == sessionID,
                      self.virtualDisplayBridge.isRequestActive(request),
                      self.isExternalDisplayRunning else { return }
                self.externalDisplayInputSynthesizer.handleInputPayload(payload)
            }
        }
        externalDisplayInputSynthesizer.permissionFailureHandler = { [weak self] in
            Task { @MainActor in
                self?.externalDisplayStatusText = "갤럭시 터치 클릭을 쓰려면 macOS 손쉬운 사용에서 MtoG를 허용하세요"
            }
        }
        refreshTrustSummary()
        bindSessionState()
        bindClipboardSync()
        clipboardCoordinator.statusHandler = { [weak self] status in
            self?.clipboardAuthority = status
            switch status {
            case .negotiating:
                self?.automaticClipboardStatus = "클립보드 협상 중 · 읽기 권한 확인 대기"
            case .permissionRequired(let reason):
                self?.automaticClipboardStatus = "확인 필요: \(reason)"
            case .unsupported(let reason):
                self?.automaticClipboardStatus = "기능 미지원: \(reason)"
            case .available:
                self?.automaticClipboardStatus = "자동 텍스트 클립보드 사용 가능"
            case .blocked(let reason):
                self?.automaticClipboardStatus = "BLOCKED: \(reason)"
            case .stopped:
                self?.automaticClipboardStatus = "자동 클립보드 중지됨"
            case .failed(let reason):
                self?.automaticClipboardStatus = "자동 클립보드 오류: \(reason)"
            }
        }

        bindWirelessDiscovery()
    }

    var enteredPairingCode: String {
        pairingCode.joined()
    }

    func updatePairingCode(_ code: String) {
        let normalized = code.filter(\.isNumber).prefix(4)
        let padded = Array(normalized).map(String.init)
        pairingCode = padded + Array(repeating: "", count: max(0, 4 - padded.count))
        pairingStatusText = normalized.count == 4
            ? "코드 입력 완료. 갤럭시와 연결한 뒤 페어링을 저장하세요."
            : "갤럭시 앱에 표시된 4자리 코드를 입력하세요"
    }

    var canUseUSBFeatures: Bool {
        trustState.isTrusted && sessionClient.hasActiveADBSession &&
            validatedPeerSession == sessionClient.activeProtocolSessionID
    }

    var canRetryClipboard: Bool {
        guard automaticClipboardEnabled else { return false }
        switch clipboardAuthority {
        case .failed, .unsupported, .blocked: return true
        default: return false
        }
    }

    func retryAutomaticClipboard() {
        guard automaticClipboardEnabled else { return }
        clipboardCoordinator.stop()
        refreshAutomaticClipboard()
    }

    func toggleAutomaticClipboard() {
        automaticClipboardEnabled.toggle()
        if automaticClipboardEnabled { refreshAutomaticClipboard() }
        else { clipboardCoordinator.stop() }
    }

    private func refreshAutomaticClipboard() {
        guard automaticClipboardEnabled else { return }
        guard trustState.isTrusted, sessionClient.hasActiveADBSession,
              let serial = sessionClient.selectedDeviceSerial,
              let session = sessionClient.activeProtocolSessionID,
              validatedPeerSession == session,
              let adb = try? adbBridge.resolvedADBPath() else {
            automaticClipboardStatus = "신뢰된 USB 연결 대기 중"
            return
        }
        clipboardCoordinator.start(sessionID: session.uuidString, serial: serial, adbPath: adb)
    }

    func refreshDisplayPermissions() {
        screenRecordingAllowed = CGPreflightScreenCaptureAccess()
        touchInputAllowed = AXIsProcessTrusted()
    }

    func openScreenRecordingSettings() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openTouchPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func startExternalDisplayMode() {
        refreshDisplayPermissions()
        guard screenRecordingAllowed else {
            externalDisplayStatusText = "화면 기록 권한이 필요합니다. 아래 ‘화면 기록 설정’에서 MtoG를 허용하고 앱을 다시 여세요."
            return
        }
        guard trustState.isTrusted,
              sessionClient.hasActiveADBSession,
              let sessionID = sessionClient.activeProtocolSessionID else {
            externalDisplayStatusText = "신뢰된 USB 연결 후 외장 디스플레이를 시작하세요"
            return
        }
        do {
            let serial = try adbBridge.selectAuthorizedDevice(
                preferredSerial: sessionClient.selectedDeviceSerial
            )
            externalDisplayStatusText = "갤럭시 외장 디스플레이를 시작하는 중"
            virtualDisplayBridge.start(serial: serial, sessionID: sessionID, highQuality: highQualityDisplay)
        } catch {
            externalDisplayStatusText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func stopExternalDisplayMode() {
        externalDisplayInputSynthesizer.releaseAll()
        externalDisplayStatusText = "갤럭시 외장 디스플레이를 종료하는 중"
        virtualDisplayBridge.stop()
    }

    func shutdownForTermination() {
        externalDisplayInputSynthesizer.releaseAll()
        clipboardCoordinator.stop()
        clipboardSyncController.stop()
        virtualDisplayBridge.stopImmediately()
    }

    func connectADBSession() async {
        clipboardSyncStatus = "갤럭시 앱과 USB 연결을 준비하는 중"
        await sessionClient.connectOverADB()
    }

    func connectWirelessSession() async {
        let host = wirelessHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            clipboardSyncStatus = "갤럭시 IP를 입력하거나 Wi-Fi 검색을 눌러주세요"
            return
        }
        transportStatus = .secureLanCandidate
        clipboardSyncStatus = "\(host):46001 무선 연결을 여는 중"
        await sessionClient.connectOverLAN(host: host)
    }

    func startWirelessDiscovery() {
        transportStatus = .secureLanCandidate
        wirelessDiscoveryBrowser.start()
        clipboardSyncStatus = "같은 개인 Wi-Fi/LAN에서 갤럭시 앱을 찾는 중"
    }

    func stopWirelessDiscovery() {
        wirelessDiscoveryBrowser.stop()
    }

    func connectDiscoveredWirelessPeer(_ peer: WirelessDiscoveredPeer) async {
        transportStatus = .secureLanCandidate
        clipboardSyncStatus = "\(peer.name)에 Wi-Fi로 연결하는 중"
        await sessionClient.connectOverBonjour(endpoint: peer.endpoint, displayName: peer.name)
    }

    func connectFirstDiscoveredWirelessPeer() async {
        guard let peer = discoveredWirelessPeers.first else {
            clipboardSyncStatus = "찾은 갤럭시 앱이 없습니다. 갤럭시 앱을 열고 두 기기를 같은 개인 Wi-Fi에 연결하세요."
            return
        }
        await connectDiscoveredWirelessPeer(peer)
    }

    func detectWirelessHostOverUSB() {
        clipboardSyncStatus = "USB로 갤럭시 Wi-Fi IP를 확인하는 중"
        let bridge = adbBridge
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let address = try bridge.queryWirelessIPv4Address()
                DispatchQueue.main.async {
                    self?.wirelessHost = address
                    self?.clipboardSyncStatus = "갤럭시 Wi-Fi IP 확인됨: \(address)"
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                DispatchQueue.main.async {
                    self?.clipboardSyncStatus = "무선 IP 확인 실패: \(message)"
                }
            }
        }
    }

    func startPairing() {
        let code = enteredPairingCode
        guard code.count == 4 else {
            pairingStatusText = "페어링에는 4자리 코드가 필요합니다"
            return
        }

        guard sessionClient.state == .connected else {
            pairingStatusText = "먼저 USB 또는 Wi-Fi로 갤럭시와 연결하세요"
            return
        }

        pairingStatusText = "페어링 요청을 보냈습니다. 갤럭시 확인을 기다리는 중입니다."
        Task {
            await sessionClient.sendPairRequest(code: code)
        }
    }

    func pushCurrentClipboardToAndroid() {
        guard sessionClient.state == .connected else {
            clipboardSyncStatus = "클립보드를 보내려면 먼저 USB 또는 Wi-Fi로 연결하세요"
            return
        }
        guard trustState.isTrusted else {
            clipboardSyncStatus = "클립보드 동기화 전에 Mac을 페어링 저장하세요"
            return
        }
        guard let payload = clipboardSyncController.currentPayload() else {
            clipboardSyncStatus = "Mac 클립보드가 비어 있거나 지원하지 않는 형식입니다"
            return
        }

        sendSharedPayload(payload)
    }

    func chooseFileToShare() {
        guard canUseUSBFeatures else { return }
        let panel = NSOpenPanel()
        panel.title = "Galaxy로 공유할 사진 또는 파일"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let payload = clipboardSyncController.filePayload(for: url) else {
            clipboardSyncStatus = "읽을 수 있는 24MB 이하 파일을 선택하세요"
            return
        }
        sendSharedPayload(payload)
    }

    private func sendSharedPayload(_ payload: ClipboardSyncPayload) {
        clipboardSyncStatus = "현재 Mac 클립보드를 갤럭시에 보내는 중"
        let generation = sessionClient.activeSessionGeneration
        Task {
            guard trustState.isTrusted,
                  sessionClient.state == .connected,
                  sessionClient.activeSessionGeneration == generation else { return }
            await sessionClient.sendClipboardPreview(
                payload: payload.wirePayload,
                expectedGeneration: generation
            )
        }
    }

    func requestAndroidClipboardPull() {
        guard sessionClient.state == .connected else {
            clipboardSyncStatus = "갤럭시 클립보드를 가져오려면 먼저 연결하세요"
            return
        }

        if sessionClient.activeTransportDescription.hasPrefix("Wi-Fi") {
            clipboardSyncStatus = "무선에서는 갤럭시에서 복사 후 알림의 '클립보드 동기화'를 누르세요"
            return
        }

        clipboardSyncStatus = "갤럭시 앱을 열지 않고 클립보드 가져오기를 요청하는 중"
        let bridge = adbBridge
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                _ = try bridge.requestClipboardSyncService()
                DispatchQueue.main.async {
                    self?.clipboardSyncStatus = "갤럭시 클립보드 동기화를 요청했습니다"
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                DispatchQueue.main.async {
                    self?.clipboardSyncStatus = "갤럭시 클립보드 가져오기 실패: \(message)"
                }
            }
        }
    }

    func toggleClipboardHistory() {
        isClipboardHistoryVisible.toggle()
    }

    func recopyClipboardHistoryItem(_ item: ClipboardHistoryItem) {
        if clipboardSyncController.recopyHistoryItem(item) {
            clipboardSyncStatus = "클립보드 기록을 다시 복사했습니다"
        } else {
            clipboardSyncStatus = "이 기록은 더 이상 다시 복사할 수 없습니다"
        }
    }

    func downloadClipboardHistoryItem(_ item: ClipboardHistoryItem) {
        if let url = clipboardSyncController.downloadHistoryItem(item) {
            clipboardSyncStatus = "\(url.lastPathComponent)에 저장했습니다"
        } else {
            clipboardSyncStatus = "이 기록은 더 이상 저장할 수 없습니다"
        }
    }

    var adbStateText: String {
        switch sessionClient.state {
        case .idle:
            return "대기 중"
        case .preparingBridge:
            return "USB 연결 준비 중"
        case .connecting:
            return "\(sessionClient.activeTransportDescription)로 연결 중"
        case .connected:
            return "연결됨"
        case .failed(let message):
            return "실패: \(message)"
        }
    }

    private func bindSessionState() {
        sessionClient.$state
            .sink { [weak self] state in
                self?.handleSessionState(state)
                if state == .connected {
                    Task { @MainActor [weak self] in self?.refreshAutomaticClipboard() }
                }
            }
            .store(in: &cancellables)
    }

    private func bindClipboardSync() {
        clipboardSyncController.localTextHandler = { [weak self] payload in
            self?.handleLocalClipboard(payload)
        }
        clipboardSyncController.diagnosticHandler = { [weak self] message in
            self?.clipboardSyncStatus = message
        }

        sessionClient.$lastReceivedMessage
            .compactMap { $0 }
            .sink { [weak self] message in
                self?.handleInboundMessage(message)
            }
            .store(in: &cancellables)
    }

    private func bindWirelessDiscovery() {
        wirelessDiscoveryBrowser.$statusText
            .sink { [weak self] status in
                self?.wirelessDiscoveryStatus = status
            }
            .store(in: &cancellables)

        wirelessDiscoveryBrowser.$peers
            .sink { [weak self] peers in
                self?.discoveredWirelessPeers = peers
            }
            .store(in: &cancellables)
    }

    private func handleSessionState(_ state: SessionClient.State) {
        switch state {
        case .idle:
            stopSessionOwnedProcesses()
            if connectionStatus == .active {
                connectionStatus = .disconnected
            }
            if connectionStatus != .active {
                connectionStatus = .disconnected
            }
            trustState.lastSeenDescription = "현재 연결 없음"
            pairingStatusText = trustState.isTrusted
                ? "저장된 기기가 있습니다. 갤럭시 앱을 열고 USB 또는 Wi-Fi로 연결하세요."
                : "갤럭시 앱에 표시된 4자리 코드를 이 Mac에 입력하세요"
        case .preparingBridge, .connecting:
            stopSessionOwnedProcesses()
            connectionStatus = .pairing
            trustState.lastSeenDescription = "연결 중"
        case .connected:
            if connectionStatus != .active {
                connectionStatus = trustState.isTrusted ? .trusted : .pairing
            }
            transportStatus = sessionClient.activeTransportDescription.hasPrefix("Wi-Fi")
                ? .secureLanCandidate
                : .adbMvp
            trustState.lastSeenDescription = "현재 연결됨"
            clipboardSyncStatus = sessionClient.activeTransportDescription.hasPrefix("Wi-Fi")
                ? "Wi-Fi 클립보드 동기화 준비됨"
                : "USB 클립보드 동기화 준비됨"
            pairingStatusText = trustState.isTrusted
                ? "저장된 기기로 다시 연결할 수 있습니다"
                : "연결됨. 갤럭시에 표시된 4자리 코드를 입력하고 페어링을 저장하세요."
        case .failed:
            stopSessionOwnedProcesses()
            if connectionStatus == .active {
                connectionStatus = .disconnected
            }
            if connectionStatus != .active {
                connectionStatus = .disconnected
            }
            trustState.lastSeenDescription = "현재 연결 없음"
            pairingStatusText = "연결 실패. USB를 다시 연결하거나 같은 개인 Wi-Fi에서 검색하세요."
            clipboardSyncStatus = "클립보드 동기화 일시 중지"
        }
    }

    private func stopSessionOwnedProcesses() {
        validatedPeerSession = nil
        clipboardCoordinator.stop()
        externalDisplayInputSynthesizer.releaseAll()
        virtualDisplayBridge.stop()
    }

    private func handleLocalClipboard(_ payload: ClipboardSyncPayload) {
        guard !automaticClipboardEnabled || (payload.kind != .text && payload.kind != .url) else { return }
        appendClipboardHistory(
            payload: payload,
            detail: clipboardDetail(for: payload, source: "Mac 클립보드"),
            sizeLabel: humanSize(payload.sizeInBytes)
        )

        guard !automaticClipboardEnabled || (payload.kind != .text && payload.kind != .url) else { return }
        guard sessionClient.state == .connected else {
            clipboardSyncStatus = "연결 후 Mac 클립보드를 보낼 수 있습니다"
            return
        }
        guard trustState.isTrusted else {
            clipboardSyncStatus = "페어링 저장 후 Mac 클립보드를 보낼 수 있습니다"
            return
        }

        clipboardSyncStatus = "Mac 클립보드를 갤럭시에 보냈습니다"
        let generation = sessionClient.activeSessionGeneration
        Task {
            guard trustState.isTrusted,
                  sessionClient.state == .connected,
                  sessionClient.activeSessionGeneration == generation else { return }
            await sessionClient.sendClipboardPreview(
                payload: payload.wirePayload,
                expectedGeneration: generation
            )
        }
    }

    private func handleInboundMessage(_ message: SessionEnvelope) {
        if message.type == .helloAck {
            handleHelloAck(message)
        }

        if message.type == .pairResult {
            handlePairResult(message)
        }

        guard message.type == .clipboardPreview else {
            return
        }
        guard trustState.isTrusted else {
            clipboardSyncStatus = "신뢰되지 않은 기기의 클립보드를 거절했습니다"
            return
        }

        if ClipboardSyncPayload.isFromLocalSource(message.payload) {
            clipboardSyncStatus = "방금 보낸 클립보드 반사를 무시했습니다"
            return
        }

        guard let payload = ClipboardSyncPayload.fromWirePayload(message.payload) else {
            let kind = message.payload["kind"] ?? "unknown"
            let size = message.payload["sizeBytes"] ?? "unknown"
            clipboardSyncStatus = "지원하지 않는 갤럭시 클립보드입니다: \(kind), \(size) B"
            return
        }

        guard !automaticClipboardEnabled || (payload.kind != .text && payload.kind != .url) else { return }
        clipboardSyncController.applyRemotePayload(payload)
        appendClipboardHistory(
            payload: payload,
            detail: clipboardDetail(for: payload, source: message.deviceName),
            sizeLabel: humanSize(payload.sizeInBytes)
        )
        clipboardSyncStatus = "갤럭시 클립보드를 받았습니다"
    }

    private func clipboardDetail(for payload: ClipboardSyncPayload, source: String) -> String {
        switch payload.kind {
        case .text, .url:
            return "\(source)에서 가져옴"
        case .image, .video, .file:
            if let mimeType = payload.mimeType, !mimeType.isEmpty {
                return "\(mimeType) · \(source)에서 가져옴"
            }
            return "\(source)에서 가져옴"
        }
    }

    private func appendClipboardHistory(
        payload: ClipboardSyncPayload,
        detail: String,
        sizeLabel: String
    ) {
        let newItem = clipboardSyncController.historyItem(
            for: payload,
            detail: detail,
            timestamp: "방금",
            sizeLabel: sizeLabel
        )
        clipboardHistory.removeAll { item in
            item.kind == newItem.kind &&
                item.title == newItem.title &&
                item.detail == newItem.detail &&
                item.sizeLabel == newItem.sizeLabel
        }
        clipboardHistory.insert(newItem, at: 0)
        if clipboardHistory.count > 50 {
            clipboardHistory = Array(clipboardHistory.prefix(50))
        }
        clipboardHistoryPersistence.save(clipboardHistory)
    }

    private func humanSize(_ sizeBytes: Int) -> String {
        if sizeBytes >= 1_000_000 {
            return String(format: "%.1f MB", Double(sizeBytes) / 1_000_000.0)
        }
        if sizeBytes >= 1_000 {
            return String(format: "%.1f KB", Double(sizeBytes) / 1_000.0)
        }
        return "\(sizeBytes) B"
    }

    private func handleHelloAck(_ message: SessionEnvelope) {


        guard let publicKeyBase64 = message.payload["publicKey"], !publicKeyBase64.isEmpty else {
            trustState.isTrusted = false
            stopSessionOwnedProcesses()
            pairingStatusText = "연결됐지만 상대 기기 정보를 아직 받지 못했습니다."
            return
        }

        if let trustedPeer = trustedPeerStore.peer(deviceId: message.deviceId, publicKeyBase64: publicKeyBase64) {
            trustedPeerStore.upsert(
                deviceId: trustedPeer.deviceId,
                deviceName: message.deviceName,
                publicKeyBase64: publicKeyBase64
            )
            trustState = TrustState(
                isTrusted: true,
                lastPairedDescription: "신뢰된 기기 · 자동 재연결 가능",
                lastSeenDescription: "방금 연결됨"
            )
            validatedPeerSession = UUID(uuidString: message.sessionId)
            connectionStatus = .trusted
            pairingStatusText = "\(message.deviceName)와 신뢰 연결이 활성화됐습니다"
            refreshTrustSummary()
            refreshAutomaticClipboard()
            clipboardSyncStatus = "신뢰된 기기와 연결됨. Mac에서 보내거나 갤럭시 알림에서 클립보드 동기화를 누르세요."
        } else {
            trustState.isTrusted = false
            stopSessionOwnedProcesses()
            trustState.lastPairedDescription = "연결된 기기가 아직 저장되지 않았습니다"
            pairingStatusText = "갤럭시에 표시된 4자리 코드로 페어링을 저장하세요"
            refreshTrustSummary()
        }
    }

    private func handlePairResult(_ message: SessionEnvelope) {
        let status = message.payload["status"] ?? "rejected"
        let publicKeyBase64 = message.payload["publicKey"] ?? ""

        guard status == "accepted", !publicKeyBase64.isEmpty else {
            pairingStatusText = message.payload["reason"] ?? "갤럭시에서 페어링을 거절했습니다"
            trustState.isTrusted = false
            stopSessionOwnedProcesses()
            return
        }

        trustedPeerStore.upsert(
            deviceId: message.deviceId,
            deviceName: message.deviceName,
            publicKeyBase64: publicKeyBase64
        )
        trustState = TrustState(
            isTrusted: true,
            lastPairedDescription: "신뢰된 기기를 이 Mac에 저장했습니다",
            lastSeenDescription: "방금 연결됨"
        )
        validatedPeerSession = UUID(uuidString: message.sessionId)
        connectionStatus = .trusted
        pairingStatusText = "페어링 완료. \(message.deviceName)을 신뢰된 기기로 저장했습니다."
        refreshTrustSummary()
        refreshAutomaticClipboard()
    }

    private func refreshTrustSummary() {
        trustedPeerCount = trustedPeerStore.allPeers().count
    }

}

enum ConnectionStatus: String {
    case disconnected = "연결 안 됨"
    case pairing = "페어링 필요"
    case trusted = "신뢰됨"
    case active = "갤럭시 조작 중"

    var subtitle: String {
        switch self {
        case .disconnected:
            return "갤럭시 연결 대기 중"
        case .pairing:
            return "4자리 코드 확인 필요"
        case .trusted:
            return "자동 재연결 준비됨"
        case .active:
            return "키보드와 포인터가 갤럭시로 전달됩니다"
        }
    }
}

enum TransportStatus: String, CaseIterable {
    case usbWaiting = "USB 연결 대기"
    case adbMvp = "USB 개발 모드"
    case aoaCandidate = "USB HID 후보"
    case secureLanCandidate = "보안 Wi-Fi 후보"

    var note: String {
        switch self {
        case .usbWaiting:
            return "USB-C 케이블은 물리 연결입니다. 현재 앱 연결에는 USB 개발 모드 또는 검증된 직접 USB 전송이 필요합니다."
        case .adbMvp:
            return "현재 구현된 USB 경로입니다. Android USB 디버깅이 필요하며 최종 제품용 전송 방식은 아닙니다."
        case .aoaCandidate:
            return "제품용 USB 목표 방식입니다. 실제 Galaxy Tab S11에서 검증이 필요합니다."
        case .secureLanCandidate:
            return "개인 네트워크용 무선 연결입니다. 페어링된 기기 인증과 암호화 세션이 필요하며 공용 Wi-Fi는 안전하다고 보지 않습니다."
        }
    }

    var next: TransportStatus {
        let values = TransportStatus.allCases
        guard let index = values.firstIndex(of: self) else { return self }
        return values[(index + 1) % values.count]
    }
}

struct TrustState {
    var isTrusted: Bool
    var lastPairedDescription: String
    var lastSeenDescription: String
}

enum ClipboardKind: String, Codable {
    case text = "Text"
    case url = "URL"
    case image = "Image"
    case video = "Video"
    case file = "File"

    var systemImage: String {
        switch self {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .image: return "photo"
        case .video: return "film"
        case .file: return "doc"
        }
    }

    var tint: String {
        switch self {
        case .text: return "#284B63"
        case .url: return "#2A7F62"
        case .image: return "#B56576"
        case .video: return "#7A4EAB"
        case .file: return "#8A5A44"
        }
    }
}

struct ClipboardHistoryItem: Identifiable, Hashable, Codable {
    let id: UUID
    let kind: ClipboardKind
    let title: String
    let detail: String
    let timestamp: String
    let sizeLabel: String
    let textValue: String?
    let mimeType: String?
    let fileName: String?
    let cachedFilePath: String?

    init(
        id: UUID = UUID(),
        kind: ClipboardKind,
        title: String,
        detail: String,
        timestamp: String,
        sizeLabel: String,
        textValue: String? = nil,
        mimeType: String? = nil,
        fileName: String? = nil,
        cachedFilePath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.sizeLabel = sizeLabel
        self.textValue = textValue
        self.mimeType = mimeType
        self.fileName = fileName
        self.cachedFilePath = cachedFilePath
    }

    var canReCopy: Bool {
        if textValue?.isEmpty == false {
            return true
        }
        guard let cachedFilePath else { return false }
        return FileManager.default.fileExists(atPath: cachedFilePath)
    }

    var canDownload: Bool {
        canReCopy
    }

    static let sampleData: [ClipboardHistoryItem] = []
}
