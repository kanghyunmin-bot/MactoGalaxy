import MtoGCore

@MainActor
protocol ClipboardBackend: ClipboardTextStore {
    var authorityStatus: ClipboardAuthorityStatus { get }
    func startMonitoring()
    func stopMonitoring()
}
