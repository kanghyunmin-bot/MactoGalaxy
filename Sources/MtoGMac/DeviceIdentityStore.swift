import CryptoKit
import Foundation

struct SessionIdentitySnapshot {
    let deviceId: String
    let deviceName: String
    let publicKeyBase64: String
}

final class DeviceIdentityStore {
    private enum Constants {
        static let keychainService = "com.mtog.identity"
        static let privateKeyAccount = "p256_signing_private_key"
        static let defaultsDeviceIdKey = "com.mtog.device-id"
    }

    private let keychainStore = KeychainStore(service: Constants.keychainService)
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func snapshot(deviceName: String) throws -> SessionIdentitySnapshot {
        let privateKey = try loadOrCreatePrivateKey()
        return SessionIdentitySnapshot(
            deviceId: loadOrCreateDeviceId(),
            deviceName: deviceName,
            publicKeyBase64: privateKey.publicKey.x963Representation.base64EncodedString()
        )
    }

    private func loadOrCreateDeviceId() -> String {
        if let existing = defaults.string(forKey: Constants.defaultsDeviceIdKey), !existing.isEmpty {
            return existing
        }

        let deviceId = UUID().uuidString
        defaults.set(deviceId, forKey: Constants.defaultsDeviceIdKey)
        return deviceId
    }

    private func loadOrCreatePrivateKey() throws -> P256.Signing.PrivateKey {
        if let stored = try keychainStore.read(account: Constants.privateKeyAccount) {
            return try P256.Signing.PrivateKey(rawRepresentation: stored)
        }

        let privateKey = P256.Signing.PrivateKey()
        try keychainStore.save(privateKey.rawRepresentation, account: Constants.privateKeyAccount)
        return privateKey
    }
}
