import Foundation

struct TrustedPeerRecord: Codable, Hashable, Identifiable {
    let deviceId: String
    let deviceName: String
    let publicKeyBase64: String
    let pairedAt: Date
    let lastSeenAt: Date

    var id: String { deviceId }

    func updatingLastSeen(at date: Date) -> TrustedPeerRecord {
        TrustedPeerRecord(
            deviceId: deviceId,
            deviceName: deviceName,
            publicKeyBase64: publicKeyBase64,
            pairedAt: pairedAt,
            lastSeenAt: date
        )
    }
}

final class TrustedPeerStore {
    private let storageURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = appSupport.appendingPathComponent("MtoG", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        storageURL = directory.appendingPathComponent("trusted-peers.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func allPeers() -> [TrustedPeerRecord] {
        guard let data = try? Data(contentsOf: storageURL),
              let peers = try? decoder.decode([TrustedPeerRecord].self, from: data) else {
            return []
        }
        return peers
    }

    func peer(deviceId: String, publicKeyBase64: String) -> TrustedPeerRecord? {
        allPeers().first { $0.deviceId == deviceId && $0.publicKeyBase64 == publicKeyBase64 }
    }

    func upsert(deviceId: String, deviceName: String, publicKeyBase64: String, seenAt: Date = Date()) {
        var peers = allPeers()
        if let index = peers.firstIndex(where: { $0.deviceId == deviceId }) {
            let existing = peers[index]
            peers[index] = TrustedPeerRecord(
                deviceId: deviceId,
                deviceName: deviceName,
                publicKeyBase64: publicKeyBase64,
                pairedAt: existing.pairedAt,
                lastSeenAt: seenAt
            )
        } else {
            peers.append(
                TrustedPeerRecord(
                    deviceId: deviceId,
                    deviceName: deviceName,
                    publicKeyBase64: publicKeyBase64,
                    pairedAt: seenAt,
                    lastSeenAt: seenAt
                )
            )
        }

        if let data = try? encoder.encode(peers) {
            try? data.write(to: storageURL, options: [.atomic])
        }
    }
}
