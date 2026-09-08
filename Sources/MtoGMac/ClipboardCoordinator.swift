import Foundation
import MtoGCore
import MtoGPlatform

@MainActor
final class ClipboardCoordinator {
    private let pasteboard: PasteboardAdapter
    private let transport: any ClipboardSessionTransport
    private let coordinator: AutomaticClipboardCoordinator
    private var activeSession: String?
    private var beganSession = false
    var statusHandler: ((ClipboardAuthorityStatus) -> Void)?

    init(sourceID: String, transport: any ClipboardSessionTransport = ShellClipboardTransport()) {
        let pasteboard = PasteboardAdapter()
        self.pasteboard = pasteboard
        self.transport = transport
        self.coordinator = AutomaticClipboardCoordinator(store: pasteboard, transport: transport,
            sourceID: sourceID, sessionID: "inactive")
        transport.statusHandler = { [weak self] status in
            guard let self else { return }
            switch status {
            case .available, .negotiating, .permissionRequired:
                if let sessionID = self.activeSession {
                    if !self.beganSession {
                        self.coordinator.start(sessionID: sessionID)
                        self.beganSession = true
                    }
                    self.pasteboard.startMonitoring()
                }
            default: self.pasteboard.stopMonitoring()
            }
            self.statusHandler?(status)
        }
    }

    func start(sessionID: String, serial: String, adbPath: String) {
        guard activeSession != sessionID else { return }
        beganSession = false
        activeSession = sessionID
        let server = [
            Bundle.main.resourceURL?.appendingPathComponent("scrcpy-server-3.3.4").path,
            "/opt/homebrew/share/scrcpy/scrcpy-server",
            "/usr/local/share/scrcpy/scrcpy-server"
        ].compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0) } ?? ""
        transport.start(configuration: .init(adbURL: URL(fileURLWithPath: adbPath), serverURL: URL(fileURLWithPath: server)),
            serial: serial, sessionID: sessionID, trusted: true)
    }

    func stop() {
        activeSession = nil
        beganSession = false
        pasteboard.stopMonitoring()
        coordinator.stop()
    }
}
