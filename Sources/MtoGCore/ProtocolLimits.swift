public enum ProtocolLimits {
    public static let version = 2
    public static let controlPayloadBytes = 36 * 1024 * 1024
    public static let videoPayloadBytes = 8 * 1024 * 1024
    public static let videoConfigBytes = 256 * 1024
    public static let videoControlBytes = 64 * 1024
    public static let maximumVideoDimension = 8_192
    public static let automaticClipboardBytes = 256 * 1024
}
