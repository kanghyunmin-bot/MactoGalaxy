import Foundation

enum SessionMessageType: String, Codable {
    case hello
    case helloAck
    case pairRequest
    case pairResult
    case enterControlMode
    case exitControlMode
    case remoteTap
    case remoteGesture
    case remotePinch
    case remoteTouchStart
    case remoteTouchMove
    case remoteTouchEnd
    case remoteBack
    case remoteHome
    case remotePointerUpdate
    case remoteText
    case remoteDeleteBackward
    case remoteEnterKey
    case ping
    case pong
    case clipboardPreview
    case error
}

struct SessionEnvelope: Codable, Identifiable {
    let id: UUID
    let sessionId: String
    let sequenceNo: UInt64
    let requiresAck: Bool
    let type: SessionMessageType
    let sentAt: Date
    let deviceId: String
    let deviceName: String
    let payload: [String: String]

    init(
        id: UUID = UUID(),
        sessionId: String = UUID().uuidString,
        sequenceNo: UInt64 = 0,
        requiresAck: Bool = false,
        type: SessionMessageType,
        sentAt: Date = Date(),
        deviceId: String,
        deviceName: String,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sequenceNo = sequenceNo
        self.requiresAck = requiresAck
        self.type = type
        self.sentAt = sentAt
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.payload = payload
    }
}

enum SessionCodec {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encodeLine(_ message: SessionEnvelope) throws -> Data {
        var data = try encoder.encode(message)
        data.append(0x0A)
        return data
    }

    static func decodeLine(_ data: Data) throws -> SessionEnvelope {
        try decoder.decode(SessionEnvelope.self, from: data)
    }
}
