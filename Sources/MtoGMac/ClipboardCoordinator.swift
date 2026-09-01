import MtoGCore

@MainActor
final class ClipboardCoordinator {
    private let pasteboard: PasteboardAdapter
    private let transport: ShellClipboardTransport
    private let coordinator: AutomaticClipboardCoordinator

    var statusHandler: ((ClipboardAuthorityStatus) -> Void)?

    init(sourceID: String) {
        let pasteboard = PasteboardAdapter()
        let transport = ShellClipboardTransport()
        self.pasteboard = pasteboard
        self.transport = transport
        self.coordinator = AutomaticClipboardCoordinator(
            store: pasteboard,
            transport: transport,
            sourceID: sourceID,
            sessionID: "inactive"
        )
    }

    func start(sessionID: String) {
        let status = coordinator.start(sessionID: sessionID)
        if status == .available {
            pasteboard.startMonitoring()
        }
        statusHandler?(status)
    }

    func stop() {
        pasteboard.stopMonitoring()
        coordinator.stop()
        statusHandler?(.stopped)
    }
}
