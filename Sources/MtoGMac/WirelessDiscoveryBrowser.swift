import Foundation
import Network

struct WirelessDiscoveredPeer: Identifiable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    let detail: String
}

@MainActor
final class WirelessDiscoveryBrowser: NSObject, ObservableObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    static let serviceType = "_mtog._tcp."

    @Published private(set) var peers: [WirelessDiscoveredPeer] = []
    @Published private(set) var statusText = "Wi-Fi 검색 대기 중"

    private var browser: NetServiceBrowser?
    private var servicesById: [String: NetService] = [:]

    func start() {
        guard browser == nil else {
            updateStatus(peers.isEmpty ? "갤럭시 탭을 찾는 중" : "MtoG 기기 \(peers.count)개 발견")
            return
        }

        updatePeers([])
        updateStatus("갤럭시 탭을 찾는 중")

        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.includesPeerToPeer = true
        self.browser = browser
        browser.searchForServices(ofType: Self.serviceType, inDomain: "")
    }

    func stop() {
        browser?.stop()
        browser?.delegate = nil
        browser = nil
        servicesById.values.forEach { $0.delegate = nil }
        servicesById.removeAll()
        updatePeers([])
        updateStatus("Wi-Fi 검색을 중지했습니다")
    }

    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        updateStatus("갤럭시 탭을 찾는 중")
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        if self.browser == nil {
            updateStatus("Wi-Fi 검색을 중지했습니다")
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        self.browser = nil
        updatePeers([])
        updateStatus("Wi-Fi 검색 실패: \(Self.errorLabel(errorDict))")
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        let id = serviceId(service)
        servicesById[id] = service
        service.delegate = self
        service.resolve(withTimeout: 5)
        publishPendingService(service)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        let id = serviceId(service)
        servicesById[id]?.delegate = nil
        servicesById.removeValue(forKey: id)
        updatePeers(peers.filter { $0.id != id })
        updateStatus(peers.isEmpty ? "갤럭시 탭을 찾는 중" : "MtoG 기기 \(peers.count)개 발견")
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        publishResolvedService(sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        publishPendingService(sender)
    }

    private func publishPendingService(_ service: NetService) {
        let endpoint = NWEndpoint.service(
            name: service.name,
            type: service.type.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            domain: service.domain,
            interface: nil
        )
        upsertPeer(
            WirelessDiscoveredPeer(
                id: serviceId(service),
                name: service.name,
                endpoint: endpoint,
                detail: "\(service.type) · 주소 확인 중"
            )
        )
    }

    private func publishResolvedService(_ service: NetService) {
        let endpoint: NWEndpoint
        let port = UInt16(exactly: service.port).flatMap(NWEndpoint.Port.init(rawValue:))
        if let hostName = service.hostName, let port {
            endpoint = .hostPort(host: NWEndpoint.Host(hostName), port: port)
        } else {
            endpoint = .service(
                name: service.name,
                type: service.type.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
                domain: service.domain,
                interface: nil
            )
        }

        let detail = [
            service.hostName,
            service.port > 0 ? "\(service.port)" : nil,
            service.domain
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        upsertPeer(
            WirelessDiscoveredPeer(
                id: serviceId(service),
                name: service.name,
                endpoint: endpoint,
                detail: detail.isEmpty ? "\(service.type) · 로컬 네트워크" : detail
            )
        )
    }

    private func upsertPeer(_ peer: WirelessDiscoveredPeer) {
        var peers = self.peers.filter { $0.id != peer.id }
        peers.append(peer)
        peers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.peers = peers
        self.statusText = "MtoG 기기 \(peers.count)개 발견"
    }

    private func updatePeers(_ peers: [WirelessDiscoveredPeer]) {
        self.peers = peers
    }

    private func updateStatus(_ status: String) {
        self.statusText = status
    }

    private func serviceId(_ service: NetService) -> String {
        "\(service.name)|\(service.type)|\(service.domain)"
    }

    private static func errorLabel(_ errorDict: [String: NSNumber]) -> String {
        let code = errorDict[NetService.errorCode]?.stringValue ?? "unknown"
        let domain = errorDict[NetService.errorDomain]?.stringValue ?? "NetService"
        return "\(domain) \(code)"
    }
}
