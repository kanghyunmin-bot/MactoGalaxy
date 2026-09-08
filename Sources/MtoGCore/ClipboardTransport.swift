public enum ClipboardAuthorityStatus: Equatable, Sendable {
    case available
    case negotiating
    case permissionRequired(String)
    case unsupported(String)
    case blocked(String)
    case stopped
    case failed(String)
}

@MainActor
public protocol ClipboardTextStore: AnyObject {
    var changeHandler: ((AutomaticClipboardKind, String) -> Void)? { get set }
    func write(kind: AutomaticClipboardKind, content: String)
}

@MainActor
public protocol ClipboardEventTransport: AnyObject {
    var status: ClipboardAuthorityStatus { get }
    var receiveHandler: ((ClipboardEvent) -> Void)? { get set }
    func send(_ event: ClipboardEvent)
    func stop()
}

@MainActor
public final class AutomaticClipboardCoordinator {
    public private(set) var status: ClipboardAuthorityStatus = .stopped

    private let store: ClipboardTextStore
    private let transport: ClipboardEventTransport
    private let engine: ClipboardSyncEngine
    private var applyingRemote = false
    private var activeSessionID: String?

    public init(store: ClipboardTextStore, transport: ClipboardEventTransport, sourceID: String, sessionID: String) {
        self.store = store
        self.transport = transport
        self.engine = ClipboardSyncEngine(sourceID: sourceID, sessionID: sessionID)
    }

    @discardableResult
    public func start(sessionID: String) -> ClipboardAuthorityStatus {
        if activeSessionID != sessionID {
            engine.begin(sessionID: sessionID)
            activeSessionID = sessionID
        }
        status = transport.status
        switch status {
        case .available, .negotiating, .permissionRequired: break
        default: return status
        }

        store.changeHandler = { [weak self] kind, content in
            guard let self, !self.applyingRemote else { return }
            do {
                self.transport.send(try self.engine.makeLocalEvent(kind: kind, content: content))
            } catch let error as ClipboardEventError {
                self.status = .failed(String(describing: error))
            } catch {
                self.status = .failed("clipboard event failed")
            }
        }
        transport.receiveHandler = { [weak self] event in
            guard let self else { return }
            guard case .accepted(let content) = self.engine.receive(event) else { return }
            self.applyingRemote = true
            self.store.write(kind: event.kind, content: content)
            self.applyingRemote = false
        }
        return status
    }

    public func stop() {
        activeSessionID = nil
        store.changeHandler = nil
        transport.receiveHandler = nil
        transport.stop()
        status = .stopped
    }
}

@MainActor
public final class InMemoryClipboardStore: ClipboardTextStore {
    public var changeHandler: ((AutomaticClipboardKind, String) -> Void)?
    public private(set) var kind: AutomaticClipboardKind?
    public private(set) var content: String?

    public init() {}

    public func write(kind: AutomaticClipboardKind, content: String) {
        self.kind = kind
        self.content = content
        changeHandler?(kind, content)
    }

    public func simulateLocalCopy(kind: AutomaticClipboardKind, content: String) {
        write(kind: kind, content: content)
    }
}

@MainActor
public final class InMemoryClipboardTransport: ClipboardEventTransport {
    public var status: ClipboardAuthorityStatus
    public var receiveHandler: ((ClipboardEvent) -> Void)?
    public weak var peer: InMemoryClipboardTransport?

    public init(status: ClipboardAuthorityStatus = .available) {
        self.status = status
    }

    public func send(_ event: ClipboardEvent) {
        guard status == .available else { return }
        peer?.receiveHandler?(event)
    }

    public func stop() {
        status = .stopped
    }
}
