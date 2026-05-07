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
    @Published var usbCableLabel = "USB-C / Thunderbolt 4 cable attached"
    @Published var trustState = TrustState(
        isTrusted: false,
        lastPairedDescription: "No trusted peer yet",
        lastSeenDescription: "Never seen"
    )
    @Published var pairingCode = ["1", "4", "0", "8"]
    @Published var clipboardHistory: [ClipboardHistoryItem]
    @Published var isClipboardHistoryVisible = false
    @Published private(set) var edgeInstructionText = ""
    @Published private(set) var lastEdgeEventDescription = "Waiting for pointer edge"
    @Published private(set) var clipboardSyncStatus = "Manual clipboard sync idle"
    @Published private(set) var pairingStatusText = "Enter the same 4-digit code on both devices"
    @Published private(set) var trustedPeerCount = 0
    @Published private(set) var controlStatusText = "Remote control actions are idle"
    @Published private(set) var macInputProfile = MacInputSystemProfile()
    @Published private(set) var controlTuningProfile = ControlInputTuningProfile.standard
    @Published private(set) var aoaHidStatusText = "AOA HID bridge idle"
    @Published private(set) var isAoaHidRunning = false
    @Published private(set) var mirrorStatusText = "Mirror Mode idle"
    @Published private(set) var isMirrorRunning = false
    @Published private(set) var externalDisplayStatusText = "External Display idle"
    @Published private(set) var isExternalDisplayRunning = false

    let transportCoordinator = TransportCoordinator()
    let sessionClient: SessionClient
    let aoaHidBridge: AoaHidBridge
    let scrcpyMirrorBridge: ScrcpyMirrorBridge
    let virtualDisplayBridge: VirtualDisplayBridge
    let externalDisplayInputSynthesizer: ExternalDisplayInputSynthesizer
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
                self?.externalDisplayStatusText = "Enable Accessibility for MtoG to allow Galaxy touch clicks"
            }
        }
        controlInputController.updateTuningProfile(controlTuningProfile)
        edgeMonitor.start()
        refreshEdgeInstruction()
        refreshTrustSummary()
        bindSessionState()
        bindClipboardSync()
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
            ? "Local code saved. Use Pair & Trust after the Android listener is connected."
            : "Enter all 4 digits on both devices"
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
        aoaHidStatusText = "Starting AOA HID bridge"
        aoaHidBridge.start()
    }

    func stopAoaHidBridge() {
        aoaHidStatusText = "Stopping AOA HID bridge"
        aoaHidBridge.stop()
    }

    func startMirrorMode() {
        mirrorStatusText = "Starting USB Mirror"
        scrcpyMirrorBridge.start()
    }

    func stopMirrorMode() {
        mirrorStatusText = "Stopping Mirror Mode"
        scrcpyMirrorBridge.stop()
    }

    func startExternalDisplayMode() {
        guard allowExperimentalExternalDisplay else {
            externalDisplayStatusText = "External Display is disabled. Enable it in Details > Experimental first."
            return
        }
        if isMirrorRunning {
            stopMirrorMode()
        }
        externalDisplayStatusText = "Starting Galaxy External Display"
        virtualDisplayBridge.start()
    }

    func stopExternalDisplayMode() {
        externalDisplayStatusText = "Stopping Galaxy External Display"
        virtualDisplayBridge.stop()
    }

    func shutdownForTermination() {
        scrcpyMirrorBridge.stop()
        virtualDisplayBridge.stopImmediately()
    }

    func connectADBSession() async {
        clipboardSyncStatus = "Starting Android companion and ADB bridge"
        await sessionClient.connectOverADB()
    }

    func connectWirelessSession() async {
        let host = wirelessHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            clipboardSyncStatus = "Enter the Galaxy wireless IP shown in the Android app"
            return
        }
        transportStatus = .secureLanCandidate
        clipboardSyncStatus = "Opening wireless LAN session to \(host):46001"
        await sessionClient.connectOverLAN(host: host)
    }

    func detectWirelessHostOverUSB() {
        clipboardSyncStatus = "Detecting Galaxy Wi-Fi IP over USB"
        let bridge = adbBridge
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let address = try bridge.queryWirelessIPv4Address()
                DispatchQueue.main.async {
                    self?.wirelessHost = address
                    self?.clipboardSyncStatus = "Detected Galaxy Wi-Fi IP: \(address)"
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                DispatchQueue.main.async {
                    self?.clipboardSyncStatus = "Wireless IP detection failed: \(message)"
                }
            }
        }
    }

    func exitAndroidControlMode() {
        controlInputController.deactivate()
        connectionStatus = sessionClient.state == .connected || isAoaHidRunning ? .trusted : .disconnected
        lastEdgeEventDescription = "Returned control to Mac"
        controlStatusText = "Returned control to Mac"
    }

    func startPairing() {
        let code = enteredPairingCode
        guard code.count == 4 else {
            pairingStatusText = "Pairing requires a full 4-digit code"
            return
        }

        guard sessionClient.state == .connected else {
            pairingStatusText = "Connect USB Dev Mode or Wireless LAN first"
            return
        }

        pairingStatusText = "Pair request sent. Waiting for Android confirmation."
        Task {
            await sessionClient.sendPairRequest(code: code)
        }
    }

    func pushCurrentClipboardToAndroid() {
        guard sessionClient.state == .connected else {
            clipboardSyncStatus = "Connect a USB or Wireless session before pushing clipboard"
            return
        }
        guard trustState.isTrusted else {
            clipboardSyncStatus = "Pair and trust this Mac before clipboard sync"
            return
        }
        guard let payload = clipboardSyncController.currentPayload() else {
            clipboardSyncStatus = "Mac clipboard is empty or unsupported"
            return
        }

        clipboardSyncStatus = "Pushing current Mac clipboard to Android"
        Task {
            await sessionClient.sendClipboardPreview(payload: payload.wirePayload)
        }
    }

    func requestAndroidClipboardPull() {
        guard sessionClient.state == .connected else {
            clipboardSyncStatus = "Connect a session before pulling clipboard"
            return
        }

        if sessionClient.activeTransportDescription.hasPrefix("Wireless LAN") {
            clipboardSyncStatus = "Wireless pull uses the Galaxy notification action: tap Sync Clipboard after copying"
            return
        }

        clipboardSyncStatus = "Requesting Android clipboard pull without opening the app"
        let bridge = adbBridge
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                _ = try bridge.requestClipboardSyncService()
                DispatchQueue.main.async {
                    self?.clipboardSyncStatus = "Android clipboard service sync requested"
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                DispatchQueue.main.async {
                    self?.clipboardSyncStatus = "Android clipboard pull failed: \(message)"
                }
            }
        }
    }

    func toggleClipboardHistory() {
        isClipboardHistoryVisible.toggle()
    }

    func recopyClipboardHistoryItem(_ item: ClipboardHistoryItem) {
        if clipboardSyncController.recopyHistoryItem(item) {
            clipboardSyncStatus = "Re-copied \(item.kind.rawValue.lowercased()) history item"
        } else {
            clipboardSyncStatus = "History item is no longer available to re-copy"
        }
    }

    func downloadClipboardHistoryItem(_ item: ClipboardHistoryItem) {
        if let url = clipboardSyncController.downloadHistoryItem(item) {
            clipboardSyncStatus = "Downloaded history item to \(url.lastPathComponent)"
        } else {
            clipboardSyncStatus = "History item is no longer available to download"
        }
    }

    var adbStateText: String {
        switch sessionClient.state {
        case .idle:
            return "Idle"
        case .preparingBridge:
            return "Preparing ADB bridge"
        case .connecting:
            return "Connecting over \(sessionClient.activeTransportDescription)"
        case .connected:
            return "Connected"
        case .failed(let message):
            return "Failed: \(message)"
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
            trustState.lastSeenDescription = "No active session"
            pairingStatusText = trustState.isTrusted
                ? "Trusted reconnect available. Connect USB when the Galaxy is attached."
                : "Enter the same 4-digit code on both devices"
        case .preparingBridge, .connecting:
            connectionStatus = .pairing
            trustState.lastSeenDescription = "Connecting"
        case .connected:
            if connectionStatus != .active {
                connectionStatus = trustState.isTrusted ? .trusted : .pairing
            }
            transportStatus = sessionClient.activeTransportDescription.hasPrefix("Wireless LAN")
                ? .secureLanCandidate
                : .adbMvp
            trustState.lastSeenDescription = "Live session active now"
            clipboardSyncStatus = sessionClient.activeTransportDescription.hasPrefix("Wireless LAN")
                ? "Manual clipboard sync ready over Wireless LAN"
                : "Manual clipboard sync ready over USB ADB Dev Mode"
            pairingStatusText = trustState.isTrusted
                ? "Trusted reconnect available"
                : "Connected. Enter the same 4-digit code and press Pair & Trust."
        case .failed:
            if connectionStatus == .active {
                controlInputController.deactivate()
                connectionStatus = .disconnected
            }
            if connectionStatus != .active {
                connectionStatus = .disconnected
            }
            trustState.lastSeenDescription = "No active session"
            pairingStatusText = "Connection failed. Reconnect USB and allow Galaxy USB debugging."
            clipboardSyncStatus = "Manual clipboard sync paused"
        }
    }

    private func refreshEdgeInstruction() {
        edgeInstructionText = "Move pointer into the top-right corner within \(Int(edgeThreshold)) pt to enter Android control mode. Return by moving the Android cursor into the bottom-left corner."
    }

    private func handleCornerActivation(corner: ControlCorner, location: CGPoint) {
        guard connectionStatus != .active else { return }
        lastEdgeEventDescription = "\(corner.displayName) trigger at x:\(Int(location.x)) y:\(Int(location.y))"
        guard isAoaHidRunning else {
            lastEdgeEventDescription += " · starting AOA HID native input"
            controlStatusText = "Starting native AOA HID for Android external keyboard/mouse input."
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
        lastEdgeEventDescription = "Android control mode entered from \(trigger.displayName.lowercased())"
        controlStatusText = "Android 입력 캡처 준비 중"
        controlInputController.activate(trigger: trigger, initialPointerLocation: pointerLocation)
    }

    private func handleLocalClipboard(_ payload: ClipboardSyncPayload) {
        appendClipboardHistory(
            payload: payload,
            detail: clipboardDetail(for: payload, source: "Mac clipboard"),
            sizeLabel: humanSize(payload.sizeInBytes)
        )

        guard sessionClient.state == .connected else {
            clipboardSyncStatus = "Mac clipboard event waiting for session"
            return
        }
        guard trustState.isTrusted else {
            clipboardSyncStatus = "Mac clipboard event blocked until peer is trusted"
            return
        }

        clipboardSyncStatus = "Sent \(payload.kind.rawValue.lowercased()) clipboard to Android"
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
            clipboardSyncStatus = "Ignored local clipboard echo"
            return
        }

        guard let payload = ClipboardSyncPayload.fromWirePayload(message.payload) else {
            let kind = message.payload["kind"] ?? "unknown"
            let size = message.payload["sizeBytes"] ?? "unknown"
            clipboardSyncStatus = "Ignored unsupported Android clipboard payload: \(kind), \(size) B"
            return
        }

        clipboardSyncController.applyRemotePayload(payload)
        appendClipboardHistory(
            payload: payload,
            detail: clipboardDetail(for: payload, source: message.deviceName),
            sizeLabel: humanSize(payload.sizeInBytes)
        )
        clipboardSyncStatus = "Received \(payload.kind.rawValue.lowercased()) clipboard from Android"
    }

    private func clipboardDetail(for payload: ClipboardSyncPayload, source: String) -> String {
        switch payload.kind {
        case .text, .url:
            return "From \(source)"
        case .image, .video, .file:
            if let mimeType = payload.mimeType, !mimeType.isEmpty {
                return "\(mimeType) · From \(source)"
            }
            return "From \(source)"
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
            timestamp: "Now",
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
            pairingStatusText = "Connected. Peer identity not advertised yet."
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
                lastPairedDescription: "Trusted peer · auto reconnect eligible",
                lastSeenDescription: "Last seen now"
            )
            connectionStatus = .trusted
            pairingStatusText = "Trusted reconnect active for \(message.deviceName)"
            refreshTrustSummary()
            clipboardSyncStatus = "Trusted peer connected. Use Push Clipboard or the Galaxy notification Sync Clipboard action."
        } else {
            trustState.isTrusted = false
            trustState.lastPairedDescription = "Connected peer is not trusted yet"
            pairingStatusText = "Connected peer requires 4-digit pairing"
            refreshTrustSummary()
        }
    }

    private func handlePairResult(_ message: SessionEnvelope) {
        let status = message.payload["status"] ?? "rejected"
        let publicKeyBase64 = message.payload["publicKey"] ?? ""

        guard status == "accepted", !publicKeyBase64.isEmpty else {
            pairingStatusText = message.payload["reason"] ?? "Pairing rejected by Android"
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
            lastPairedDescription: "Trusted device stored locally",
            lastSeenDescription: "Last seen now"
        )
        connectionStatus = .trusted
        pairingStatusText = "Pairing complete. Trusted reconnect stored for \(message.deviceName)."
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
    case disconnected = "Disconnected"
    case pairing = "Pairing"
    case trusted = "Trusted"
    case active = "Android Control Mode"

    var subtitle: String {
        switch self {
        case .disconnected:
            return "Waiting for tablet session"
        case .pairing:
            return "4-digit confirmation pending"
        case .trusted:
            return "Ready to auto reconnect"
        case .active:
            return "Keyboard and pointer routed to Android"
        }
    }
}

enum TransportStatus: String, CaseIterable {
    case usbWaiting = "USB Direct Pending"
    case adbMvp = "USB ADB Dev Mode"
    case aoaCandidate = "USB AOA Candidate"
    case secureLanCandidate = "Secure LAN Candidate"

    var note: String {
        switch self {
        case .usbWaiting:
            return "USB-C is the physical link. The app still needs ADB Dev Mode or a validated direct USB transport."
        case .adbMvp:
            return "Current implementation path. Requires Android USB debugging and is not the final production transport."
        case .aoaCandidate:
            return "Production USB target. Must be validated on real Galaxy Tab S11 hardware."
        case .secureLanCandidate:
            return "Private-network fallback target. Must use paired-device authentication and encrypted app sessions; public/shared Wi-Fi is not assumed safe."
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
