import Foundation

public enum SessionMessageType: String, Codable, CaseIterable, Sendable {
    case hello
    case helloAck
    case helloConfirm
    case helloConfirmed
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

public struct SessionEnvelope: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionId: String
    public let sequenceNo: UInt64
    public let requiresAck: Bool
    public let type: SessionMessageType
    public let sentAt: String
    public let deviceId: String
    public let deviceName: String
    public let payload: [String: String]

    public init(
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
        self.init(
            id: id,
            sessionId: sessionId,
            sequenceNo: sequenceNo,
            requiresAck: requiresAck,
            type: type,
            sentAt: ISO8601DateFormatter().string(from: sentAt),
            deviceId: deviceId,
            deviceName: deviceName,
            payload: payload
        )
    }

    public init(
        id: UUID,
        sessionId: String,
        sequenceNo: UInt64,
        requiresAck: Bool,
        type: SessionMessageType,
        sentAt: String,
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
