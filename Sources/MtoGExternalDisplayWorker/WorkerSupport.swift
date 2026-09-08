import Foundation

func workerStatus(_ message: String) {
    print("status:\(message)")
    fflush(stdout)
}

enum WorkerError: Error, LocalizedError {
    case adbNotFound
    case adbFailed(String)
    case deviceMissing
    case virtualDisplayUnavailable
    case virtualDisplayCreateFailed
    case displayIdUnavailable
    case socketConnectFailed(String)
    case socketListenFailed(String)
    case streamDisconnected
    case captureFailed(String)
    case encodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .adbNotFound: return "adb binary not found"
        case .adbFailed(let reason): return "adb failed: \(reason)"
        case .deviceMissing: return "No authorized Android device found"
        case .virtualDisplayUnavailable: return "macOS virtual display API is unavailable"
        case .virtualDisplayCreateFailed: return "Could not create the Galaxy virtual display"
        case .displayIdUnavailable: return "Virtual display did not publish a display ID"
        case .socketConnectFailed(let reason): return "Could not open Galaxy display stream: \(reason)"
        case .socketListenFailed(let reason): return "Could not open Galaxy touch input server: \(reason)"
        case .streamDisconnected: return "Galaxy display stream disconnected"
        case .captureFailed(let reason): return "ScreenCaptureKit failed: \(reason)"
        case .encodeFailed(let reason): return "VideoToolbox failed: \(reason)"
        }
    }
}
