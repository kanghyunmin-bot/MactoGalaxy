import MtoGCore

@MainActor
final class ShellClipboardTransport: ClipboardEventTransport {
    let status: ClipboardAuthorityStatus = .blocked(
        "scrcpy 3.3.4에서 검증된 standalone clipboard authority를 찾지 못했습니다"
    )
    var receiveHandler: ((ClipboardEvent) -> Void)?

    func send(_ event: ClipboardEvent) {}

    func stop() {
        receiveHandler = nil
    }
}
