import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var deviceName = Host.current().localizedName ?? "Mac"
    @Published var targetName = "Galaxy Tab S11"
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var transportStatus: TransportStatus = .usbWaiting
    @Published var wirelessHost: String = UserDefaults.standard.string(forKey: "com.mtog.wireless-host") ?? "" {
        didSet {
            UserDefaults.standard.set(wirelessHost, forKey: "com.mtog.wireless-host")
        }
    }
    @Published private(set) var wirelessDiscoveryStatus = "Wi-Fi 검색 대기 중"
    @Published private(set) var discoveredWirelessPeers: [WirelessDiscoveredPeer] = []
    @Published var preferredExitHotkey = "Esc or Command + Q"
    @Published var useSystemInputSettings = true {
        didSet { persistAndApplyInputRoutingPreferences() }
    }
    @Published var manualPointerGain = 2.2 {
        didSet { persistAndApplyInputRoutingPreferences() }
    }
    @Published var manualScrollGain = 1.0 {
        didSet { persistAndApplyInputRoutingPreferences() }
    }
    @Published var manualPinchGain = 1.0 {
        didSet { persistAndApplyInputRoutingPreferences() }
    }
    @Published var manualSwipeEnabled = true {
        didSet { persistAndApplyInputRoutingPreferences() }
    }
    @Published var manualPinchEnabled = true {
        didSet { persistAndApplyInputRoutingPreferences() }
    }
    @Published var manualHapticsEnabled = true {
        didSet { persistAndApplyInputRoutingPreferences() }
    }
    @Published var allowExperimentalExternalDisplay = UserDefaults.standard.bool(forKey: "com.mtog.experimental-external-display-enabled") {
        didSet {
            UserDefaults.standard.set(
                allowExperimentalExternalDisplay,
                forKey: "com.mtog.experimental-external-display-enabled"
            )
            if !allowExperimentalExternalDisplay {
                stopExternalDisplayMode()
            }
        }
    }
    @Published private(set) var cornerSelection: ControlCorner = .topRight
    @Published var edgeThreshold: Double = 12 {
        didSet {
            edgeMonitor.threshold = edgeThreshold
            refreshEdgeInstruction()
        }
    }
    @Published var usbCableLabel = "USB-C / Thunderbolt 4 케이블 연결됨"
    @Published var trustState = TrustState(
        isTrusted: false,
        lastPairedDescription: "아직 저장된 기기가 없습니다",
        lastSeenDescription: "연결 기록 없음"
    )
    @Published var pairingCode = ["1", "4", "0", "8"]
    @Published var clipboardHistory: [ClipboardHistoryItem]
    @Published var isClipboardHistoryVisible = false
    @Published private(set) var edgeInstructionText = ""
    @Published private(set) var lastEdgeEventDescription = "포인터 전환 대기 중"
    @Published private(set) var clipboardSyncStatus = "클립보드 동기화 대기 중"
    @Published private(set) var pairingStatusText = "양쪽 기기에 같은 4자리 코드를 입력하세요"
    @Published private(set) var trustedPeerCount = 0
    @Published private(set) var controlStatusText = "원격 조작 대기 중"
    @Published private(set) var macInputProfile = MacInputSystemProfile()
    @Published private(set) var controlTuningProfile = ControlInputTuningProfile.standard
    @Published private(set) var aoaHidStatusText = "USB HID 브리지 대기 중"
    @Published private(set) var isAoaHidRunning = false
    @Published private(set) var mirrorStatusText = "미러링 대기 중"
    @Published private(set) var isMirrorRunning = false
    @Published private(set) var externalDisplayStatusText = "외장 디스플레이 대기 중"
    @Published private(set) var isExternalDisplayRunning = false

    let transportCoordinator = TransportCoordinator()
    let sessionClient: SessionClient
    let aoaHidBridge: AoaHidBridge
    let scrcpyMirrorBridge: ScrcpyMirrorBridge
    let virtualDisplayBridge: VirtualDisplayBridge
    let externalDisplayInputSynthesizer: ExternalDisplayInputSynthesizer
    let wirelessDiscoveryBrowser: WirelessDiscoveryBrowser
    let localIdentity: SessionIdentitySnapshot

    private let deviceIdentityStore: DeviceIdentityStore
    private let adbBridge: ADBBridge
    private let inputProfileReader: MacInputSystemProfileReader
    private let inputPreferencesStore: InputRoutingPreferencesStore
    private let trustedPeerStore: TrustedPeerStore
    private let edgeMonitor: PointerEdgeMonitor
    private let clipboardSyncController: ClipboardSyncController
    private let clipboardHistoryPersistence: ClipboardHistoryPersistence
    private let controlInputController: ControlModeInputController
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.deviceIdentityStore = DeviceIdentityStore()
        self.adbBridge = ADBBridge()
        self.inputProfileReader = MacInputSystemProfileReader()
        self.inputPreferencesStore = InputRoutingPreferencesStore()
        self.trustedPeerStore = TrustedPeerStore()
        self.localIdentity = (try? deviceIdentityStore.snapshot(deviceName: Host.current().localizedName ?? "Mac"))
            ?? SessionIdentitySnapshot(
                deviceId: UUID().uuidString,
                deviceName: Host.current().localizedName ?? "Mac",
                publicKeyBase64: ""
            )
        self.sessionClient = SessionClient(identity: localIdentity)
        self.edgeMonitor = PointerEdgeMonitor()
        self.clipboardSyncController = ClipboardSyncController()
        self.clipboardHistoryPersistence = ClipboardHistoryPersistence()
        self.aoaHidBridge = AoaHidBridge()
        self.scrcpyMirrorBridge = ScrcpyMirrorBridge()
        self.virtualDisplayBridge = VirtualDisplayBridge()
        self.externalDisplayInputSynthesizer = ExternalDisplayInputSynthesizer()
        self.wirelessDiscoveryBrowser = WirelessDiscoveryBrowser()
        self.controlInputController = ControlModeInputController(
            sessionClient: sessionClient,
            hidBridge: aoaHidBridge
        )
        self.clipboardHistory = clipboardHistoryPersistence.load() ?? []
        let storedInputPreferences = inputPreferencesStore.load()
        self.useSystemInputSettings = storedInputPreferences.followSystemSettings
        self.manualPointerGain = storedInputPreferences.manualPointerGain
        self.manualScrollGain = storedInputPreferences.manualScrollGain
        self.manualPinchGain = storedInputPreferences.manualPinchGain
        self.manualSwipeEnabled = storedInputPreferences.manualSwipeEnabled
        self.manualPinchEnabled = storedInputPreferences.manualPinchEnabled
        self.manualHapticsEnabled = storedInputPreferences.manualHapticsEnabled
        let systemProfile = inputProfileReader.read()
        self.macInputProfile = systemProfile
        self.controlTuningProfile = MacInputSettingsResolver.resolve(
            systemProfile: systemProfile,
            preferences: storedInputPreferences
        )

        if let restoredCode = deviceIdentityStore.restoreLastPairingCode(), !restoredCode.isEmpty {
            applyDemoPairingCode(restoredCode)
        }

        edgeMonitor.configuredCorner = cornerSelection
        edgeMonitor.threshold = edgeThreshold
        edgeMonitor.activationHandler = { [weak self] corner, location in
            self?.handleCornerActivation(corner: corner, location: location)
        }
        controlInputController.statusHandler = { [weak self] status in
            Task { @MainActor in
                self?.controlStatusText = status
            }
        }
        controlInputController.exitHandler = { [weak self] in
            self?.exitAndroidControlMode()
        }
        aoaHidBridge.statusHandler = { [weak self] status in
            Task { @MainActor in
                self?.aoaHidStatusText = status
            }
        }
        aoaHidBridge.stateHandler = { [weak self] running in
            Task { @MainActor in
                self?.isAoaHidRunning = running
                if running {
                    self?.transportStatus = .aoaCandidate
                }
            }
        }
        scrcpyMirrorBridge.statusHandler = { [weak self] status in
            Task { @MainActor in
                self?.mirrorStatusText = status
            }
        }
        scrcpyMirrorBridge.stateHandler = { [weak self] running in
            Task { @MainActor in
                self?.isMirrorRunning = running
                if running {
                    self?.transportStatus = .adbMvp
                }
            }
        }
        virtualDisplayBridge.statusHandler = { [weak self] status in
            Task { @MainActor in
                self?.externalDisplayStatusText = status
            }
        }
        virtualDisplayBridge.stateHandler = { [weak self] running in
            Task { @MainActor in
                self?.isExternalDisplayRunning = running
                if running {
                    self?.transportStatus = .adbMvp
                }
            }
        }
        virtualDisplayBridge.inputHandler = { [weak self] payload in
            Task { @MainActor in
                self?.externalDisplayInputSynthesizer.handleInputPayload(payload)
            }
        }
        externalDisplayInputSynthesizer.permissionFailureHandler = { [weak self] in
            Task { @MainActor in
                self?.externalDisplayStatusText = "갤럭시 터치 클릭을 쓰려면 macOS 손쉬운 사용에서 MtoG를 허용하세요"
            }
        }
        controlInputController.updateTuningProfile(controlTuningProfile)
        edgeMonitor.start()
        refreshEdgeInstruction()
        refreshTrustSummary()
        bindSessionState()
        bindClipboardSync()
        bindWirelessDiscovery()
    }

    var enteredPairingCode: String {
        pairingCode.joined()
    }

    func applyDemoPairingCode(_ code: String) {
        let normalized = code.filter(\.isNumber).prefix(4)
        let padded = Array(normalized).map(String.init)
        pairingCode = padded + Array(repeating: "", count: max(0, 4 - padded.count))
        deviceIdentityStore.persistLastPairingCode(String(normalized))
        pairingStatusText = normalized.count == 4
            ? "코드를 저장했습니다. 갤럭시와 연결한 뒤 페어링을 저장하세요."
            : "양쪽 기기에 4자리 코드를 모두 입력하세요"
    }

    func refreshMacInputProfile() {
        let refreshedProfile = inputProfileReader.read()
        macInputProfile = refreshedProfile
        applyResolvedInputRoutingPreferences(
            preferences: currentInputRoutingPreferences(),
            persist: false
        )
    }

    func startAoaHidBridge() {
        aoaHidStatusText = "USB HID 브리지를 시작하는 중"
        aoaHidBridge.start()
    }

    func stopAoaHidBridge() {
        aoaHidStatusText = "USB HID 브리지를 종료하는 중"
        aoaHidBridge.stop()
    }

    func startMirrorMode() {
        mirrorStatusText = "USB 미러링을 시작하는 중"
        scrcpyMirrorBridge.start()
    }

    func stopMirrorMode() {
        mirrorStatusText = "미러링을 종료하는 중"
        scrcpyMirrorBridge.stop()
    }

    func startExternalDisplayMode() {
        guard allowExperimentalExternalDisplay else {
            externalDisplayStatusText = "외장 디스플레이가 꺼져 있습니다. 먼저 실험 기능 허용을 켜세요."
            return
        }
        if isMirrorRunning {
            stopMirrorMode()
        }
        externalDisplayStatusText = "갤럭시 외장 디스플레이를 시작하는 중"
        virtualDisplayBridge.start()
    }

    func stopExternalDisplayMode() {
        externalDisplayStatusText = "갤럭시 외장 디스플레이를 종료하는 중"
        virtualDisplayBridge.stop()
    }

    func shutdownForTermination() {
        scrcpyMirrorBridge.stop()
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

    func exitAndroidControlMode() {
        controlInputController.deactivate()
        connectionStatus = sessionClient.state == .connected || isAoaHidRunning ? .trusted : .disconnected
        lastEdgeEventDescription = "Mac 조작으로 돌아왔습니다"
        controlStatusText = "Mac 조작으로 돌아왔습니다"
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

        clipboardSyncStatus = "현재 Mac 클립보드를 갤럭시에 보내는 중"
        Task {
            await sessionClient.sendClipboardPreview(payload: payload.wirePayload)
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
            if connectionStatus == .active {
                controlInputController.deactivate()
                connectionStatus = .disconnected
            }
            if connectionStatus != .active {
                connectionStatus = .disconnected
            }
            trustState.lastSeenDescription = "현재 연결 없음"
            pairingStatusText = trustState.isTrusted
                ? "저장된 기기가 있습니다. 갤럭시 앱을 열고 USB 또는 Wi-Fi로 연결하세요."
                : "양쪽 기기에 같은 4자리 코드를 입력하세요"
        case .preparingBridge, .connecting:
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
                : "연결됨. 같은 4자리 코드를 입력하고 페어링을 저장하세요."
        case .failed:
            if connectionStatus == .active {
                controlInputController.deactivate()
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

    private func refreshEdgeInstruction() {
        edgeInstructionText = "포인터를 Mac 화면 오른쪽 위 모서리 \(Int(edgeThreshold))pt 안으로 이동하면 갤럭시 조작 모드로 들어갑니다. 갤럭시 커서를 왼쪽 아래로 보내면 Mac으로 돌아옵니다."
    }

    private func handleCornerActivation(corner: ControlCorner, location: CGPoint) {
        guard connectionStatus != .active else { return }
        lastEdgeEventDescription = "\(corner.displayName)에서 전환 감지 · x:\(Int(location.x)) y:\(Int(location.y))"
        guard isAoaHidRunning else {
            lastEdgeEventDescription += " · USB HID 입력 시작 중"
            controlStatusText = "갤럭시가 외부 키보드/마우스로 인식하도록 USB HID를 시작하는 중입니다."
            startAoaHidBridge()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, self.isAoaHidRunning, self.connectionStatus != .active else { return }
                self.enterAndroidControlMode(trigger: corner, pointerLocation: location)
            }
            return
        }

        enterAndroidControlMode(trigger: corner, pointerLocation: location)
    }

    private func enterAndroidControlMode(trigger: ControlCorner, pointerLocation: CGPoint) {
        refreshMacInputProfile()
        connectionStatus = .active
        lastEdgeEventDescription = "\(trigger.displayName)에서 갤럭시 조작 모드로 들어갔습니다"
        controlStatusText = "갤럭시 입력 캡처 준비 중"
        controlInputController.activate(trigger: trigger, initialPointerLocation: pointerLocation)
    }

    private func handleLocalClipboard(_ payload: ClipboardSyncPayload) {
        appendClipboardHistory(
            payload: payload,
            detail: clipboardDetail(for: payload, source: "Mac 클립보드"),
            sizeLabel: humanSize(payload.sizeInBytes)
        )

        guard sessionClient.state == .connected else {
            clipboardSyncStatus = "연결 후 Mac 클립보드를 보낼 수 있습니다"
            return
        }
        guard trustState.isTrusted else {
            clipboardSyncStatus = "페어링 저장 후 Mac 클립보드를 보낼 수 있습니다"
            return
        }

        clipboardSyncStatus = "Mac 클립보드를 갤럭시에 보냈습니다"
        Task {
            await sessionClient.sendClipboardPreview(payload: payload.wirePayload)
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
        if let width = Double(message.payload["displayWidth"] ?? ""),
           let height = Double(message.payload["displayHeight"] ?? ""),
           width > 0,
           height > 0 {
            controlInputController.updateRemoteDisplaySize(
                CGSize(width: width, height: height)
            )
        }

        guard let publicKeyBase64 = message.payload["publicKey"], !publicKeyBase64.isEmpty else {
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
            connectionStatus = .trusted
            pairingStatusText = "\(message.deviceName)와 신뢰 연결이 활성화됐습니다"
            refreshTrustSummary()
            clipboardSyncStatus = "신뢰된 기기와 연결됨. Mac에서 보내거나 갤럭시 알림에서 클립보드 동기화를 누르세요."
        } else {
            trustState.isTrusted = false
            trustState.lastPairedDescription = "연결된 기기가 아직 저장되지 않았습니다"
            pairingStatusText = "4자리 코드로 페어링을 저장하세요"
            refreshTrustSummary()
        }
    }

    private func handlePairResult(_ message: SessionEnvelope) {
        let status = message.payload["status"] ?? "rejected"
        let publicKeyBase64 = message.payload["publicKey"] ?? ""

        guard status == "accepted", !publicKeyBase64.isEmpty else {
            pairingStatusText = message.payload["reason"] ?? "갤럭시에서 페어링을 거절했습니다"
            trustState.isTrusted = false
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
        connectionStatus = .trusted
        pairingStatusText = "페어링 완료. \(message.deviceName)을 신뢰된 기기로 저장했습니다."
        refreshTrustSummary()
    }

    private func refreshTrustSummary() {
        trustedPeerCount = trustedPeerStore.allPeers().count
    }

    private func persistAndApplyInputRoutingPreferences() {
        applyResolvedInputRoutingPreferences(
            preferences: currentInputRoutingPreferences(),
            persist: true
        )
    }

    private func currentInputRoutingPreferences() -> InputRoutingPreferences {
        InputRoutingPreferences(
            followSystemSettings: useSystemInputSettings,
            manualPointerGain: manualPointerGain,
            manualScrollGain: manualScrollGain,
            manualPinchGain: manualPinchGain,
            manualSwipeEnabled: manualSwipeEnabled,
            manualPinchEnabled: manualPinchEnabled,
            manualHapticsEnabled: manualHapticsEnabled
        )
    }

    private func applyResolvedInputRoutingPreferences(
        preferences: InputRoutingPreferences,
        persist: Bool
    ) {
        if persist {
            inputPreferencesStore.save(preferences)
        }

        controlTuningProfile = MacInputSettingsResolver.resolve(
            systemProfile: macInputProfile,
            preferences: preferences
        )
        controlInputController.updateTuningProfile(controlTuningProfile)
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
