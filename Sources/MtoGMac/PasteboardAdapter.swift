import AppKit
import MtoGCore

@MainActor
final class PasteboardAdapter: ClipboardBackend {
    let pasteboard: NSPasteboard
    var changeHandler: ((AutomaticClipboardKind, String) -> Void)?
    let authorityStatus = ClipboardAuthorityStatus.available

    var observationHandler: (() -> Void)?

    private var timer: Timer?
    private var lastChangeCount: Int
    private var suppressedChangeCount: Int?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    func startMonitoring() {
        stopMonitoring()
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func write(kind: AutomaticClipboardKind, content: String) {
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        suppressedChangeCount = pasteboard.changeCount
    }

    func acknowledgeCurrentChange() {
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        if suppressedChangeCount == lastChangeCount {
            suppressedChangeCount = nil
            return
        }
        observationHandler?()
        guard let content = pasteboard.string(forType: .string),
              !content.isEmpty,
              content.lengthOfBytes(using: .utf8) <= ProtocolLimits.automaticClipboardBytes else {
            return
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind: AutomaticClipboardKind = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? .url
            : .text
        changeHandler?(kind, content)
    }
}
