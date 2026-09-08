public enum ADBDeviceState: String, Sendable {
    case authorized = "device"
    case unauthorized
    case offline
    case other
}

public struct ADBDevice: Equatable, Sendable {
    public let serial: String
    public let state: ADBDeviceState
    public let details: String

    public init(serial: String, state: ADBDeviceState, details: String) {
        self.serial = serial
        self.state = state
        self.details = details
    }
}

public enum ADBDeviceSelectionError: Error, Equatable {
    case noAuthorizedDevice
    case multipleAuthorized([String])
    case preferredUnavailable(String)
}

public enum ADBDeviceParser {
    public static func parse(_ output: String) -> [ADBDevice] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, fields[0] != "List" else { return nil }
            let rawState = String(fields[1])
            let state = ADBDeviceState(rawValue: rawState) ?? .other
            return ADBDevice(
                serial: String(fields[0]),
                state: state,
                details: fields.dropFirst(2).joined(separator: " ")
            )
        }
    }
}

public enum ADBDeviceSelector {
    public static func select(devices: [ADBDevice], preferredSerial: String?) throws -> ADBDevice {
        let authorized = devices.filter { $0.state == .authorized }.sorted { $0.serial < $1.serial }
        if let preferredSerial {
            guard let selected = authorized.first(where: { $0.serial == preferredSerial }) else {
                throw ADBDeviceSelectionError.preferredUnavailable(preferredSerial)
            }
            return selected
        }
        guard !authorized.isEmpty else { throw ADBDeviceSelectionError.noAuthorizedDevice }
        guard authorized.count == 1 else {
            throw ADBDeviceSelectionError.multipleAuthorized(authorized.map(\.serial))
        }
        return authorized[0]
    }
}
