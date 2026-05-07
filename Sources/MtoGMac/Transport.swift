import Foundation
import Network

protocol TransportAdapter: AnyObject {
    var kind: String { get }
    func start() async throws
    func stop()
    func send(_ payload: Data) async throws
}

final class TransportCoordinator {
    let udp = UDPTransportAdapter()
    let usb = USBDirectTransportAdapter()
}

final class UDPTransportAdapter: NSObject, TransportAdapter, @unchecked Sendable {
    let kind = "ip-fallback-experimental"

    private var connection: NWConnection?
    private var listener: NWListener?

    func start() async throws {
        // Experimental only: use IP fallback only when both devices are on a real private IP path.
        // Thunderbolt/USB-C is a physical link and does not itself create Mac-to-Android UDP routing.
        // Production fallback should use authenticated encryption above this adapter.
    }

    func startListener(on port: UInt16) throws {
        let listener = try NWListener(using: .udp, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global(qos: .userInitiated))
            self.receive(on: connection)
        }
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }

    func connect(host: String, port: UInt16) {
        let target = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .udp
        )
        target.start(queue: .global(qos: .userInitiated))
        connection = target
        receive(on: target)
    }

    func stop() {
        connection?.cancel()
        listener?.cancel()
        connection = nil
        listener = nil
    }

    func send(_ payload: Data) async throws {
        guard let connection else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { _, _, _, _ in
            if connection.state == .ready {
                self.receive(on: connection)
            }
        }
    }
}

final class USBDirectTransportAdapter: TransportAdapter {
    enum Mode: String {
        case unresolved = "unresolved"
        case adbMvp = "adb-mvp"
        case aoaCandidate = "aoa-candidate"
    }

    let kind = "usb-direct"
    var mode: Mode = .adbMvp

    func start() async throws {
        // Placeholder for ADB tunnel bootstrap or future AOA bulk transport bootstrap.
    }

    func stop() {}

    func send(_ payload: Data) async throws {
        _ = payload
    }
}
