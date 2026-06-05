import Foundation
import Security

enum KeychainStoreError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "키체인 작업이 실패했습니다. 상태 코드: \(status)"
        }
    }
}

final class KeychainStore {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func read(account: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    func save(_ data: Data, account: String) throws {
        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }

        var insertQuery = baseQuery
        insertQuery[kSecValueData] = data
        insertQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(addStatus)
        }
    }
}
