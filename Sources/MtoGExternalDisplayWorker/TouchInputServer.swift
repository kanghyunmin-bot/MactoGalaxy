import CoreGraphics
import Darwin
import Foundation

private struct TouchInputMessage {
    let action: String
    let pointerCount: Int
    let x: CGFloat
    let y: CGFloat
    let span: CGFloat?
}

private struct TouchInputState {
    var isMouseDown = false
    var lastScrollPoint: CGPoint?
    var lastPinchSpan: CGFloat?
    var pendingDownPoint: CGPoint?
    var pendingDownTime: Date?
    var longPressFired = false
    var lastTapPoint: CGPoint?
    var lastTapTime: Date?
}

final class TouchInputServer: @unchecked Sendable {
    private let inputPort: UInt16
    private let tapMoveTolerance: CGFloat = 12
    private let doubleTapTolerance: CGFloat = 42
    private let tapMaxDuration: TimeInterval = 0.35
    private let doubleTapInterval: TimeInterval = 0.48
    private let stateLock = NSLock()
    private var inputServerFD: Int32 = -1
    private var inputClientFD: Int32 = -1
    private var running = true
    private var inputThread: Thread?
    private var threadFinished: DispatchSemaphore?
    private var touchInputState = TouchInputState()

    init(port: UInt16) {
        inputPort = port
    }

    func start(displayID: CGDirectDisplayID) throws {
        stateLock.lock(); running = true; stateLock.unlock()
        try startTouchInputServer(displayID: displayID)
    }

    private var keepRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return running
    }

    private func startTouchInputServer(displayID: CGDirectDisplayID) throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw WorkerError.socketListenFailed(String(cString: strerror(errno)))
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        configureNoSigpipe(fd)

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = inputPort.bigEndian
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let reason = String(cString: strerror(errno))
            Darwin.close(fd)
            throw WorkerError.socketListenFailed(reason)
        }

        guard Darwin.listen(fd, 1) == 0 else {
            let reason = String(cString: strerror(errno))
            Darwin.close(fd)
            throw WorkerError.socketListenFailed(reason)
        }

        inputServerFD = fd
        status("Galaxy touch input channel listening")
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            defer { finished.signal() }
            self?.touchInputAcceptLoop(displayID: displayID)
        }
        threadFinished = finished
        inputThread = thread
        thread.start()
    }

    private func touchInputAcceptLoop(displayID: CGDirectDisplayID) {
        while keepRunning {
            var clientAddress = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let serverFD = currentServerFD()
            let clientFD = withUnsafeMutablePointer(to: &clientAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.accept(serverFD, sockaddrPointer, &length)
                }
            }

            if clientFD < 0 {
                if errno == EINTR {
                    continue
                }
                if keepRunning {
                    status("Galaxy touch input accept failed")
                }
                return
            }

            if !keepRunning {
                Darwin.close(clientFD)
                return
            }
            configureNoSigpipe(clientFD)
            setClientFD(clientFD)
            status("Galaxy touch input connected")
            receiveTouchInput(clientFD: clientFD, displayID: displayID)
            releaseMouseIfNeeded(displayID: displayID)
            if clearClientFD(ifMatching: clientFD) {
                Darwin.shutdown(clientFD, SHUT_RDWR)
                Darwin.close(clientFD)
            }
            if keepRunning {
                status("Galaxy touch input disconnected")
            }
        }
    }

    private func receiveTouchInput(clientFD: Int32, displayID: CGDirectDisplayID) {
        var lineBuffer = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while keepRunning {
            let received = Darwin.recv(clientFD, &buffer, buffer.count, 0)
            if received < 0 && errno == EINTR {
                continue
            }
            if received <= 0 {
                return
            }

            for byte in buffer.prefix(received) {
                if byte == 10 {
                    handleTouchInputLine(lineBuffer, displayID: displayID)
                    lineBuffer.removeAll(keepingCapacity: true)
                } else if lineBuffer.count < 4096 {
                    lineBuffer.append(byte)
                } else {
                    lineBuffer.removeAll(keepingCapacity: true)
                }
            }
        }
    }

    private func handleTouchInputLine(_ data: Data, displayID: CGDirectDisplayID) {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["type"] as? String) == "touch",
              let action = object["action"] as? String,
              let x = number(object["x"]),
              let y = number(object["y"]) else {
            return
        }

        let pointerCount = Int(number(object["pointers"]) ?? 1)
        let span = number(object["span"]).map { CGFloat($0) }
        let message = TouchInputMessage(
            action: action,
            pointerCount: max(pointerCount, 1),
            x: CGFloat(x).clamped(to: 0 ... 1),
            y: CGFloat(y).clamped(to: 0 ... 1),
            span: span
        )
        handleTouchInput(message, displayID: displayID)
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let double = value as? Double {
            return double
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private func handleTouchInput(_ message: TouchInputMessage, displayID: CGDirectDisplayID) {
        let point = displayPoint(normalizedX: message.x, normalizedY: message.y, displayID: displayID)
        let action = message.action

        if message.pointerCount >= 2 {
            if touchInputState.isMouseDown {
                postMouse(type: .leftMouseUp, point: point)
                touchInputState.isMouseDown = false
            }
            handleTwoFingerTouch(message, point: point)
            return
        }

        touchInputState.lastScrollPoint = nil
        touchInputState.lastPinchSpan = nil

        switch action {
        case "click":
            moveCursor(to: point)
            postClick(button: .left, point: point)
            clearPendingSingleTouch()
        case "right_click":
            moveCursor(to: point)
            postClick(button: .right, point: point)
            clearPendingSingleTouch()
        case "down":
            moveCursor(to: point)
            touchInputState.pendingDownPoint = point
            touchInputState.pendingDownTime = Date()
            touchInputState.longPressFired = false
        case "move":
            moveCursor(to: point)
            handleSingleFingerMove(point)
        case "up", "cancel":
            moveCursor(to: point)
            if touchInputState.isMouseDown {
                postMouse(type: .leftMouseUp, point: point)
                touchInputState.isMouseDown = false
            }
            clearPendingSingleTouch()
        default:
            break
        }
    }

    private func handleSingleFingerMove(_ point: CGPoint) {
        guard let downPoint = touchInputState.pendingDownPoint else {
            postMouse(type: .mouseMoved, point: point)
            return
        }

        if touchInputState.longPressFired {
            return
        }

        if touchInputState.isMouseDown {
            postMouse(type: .leftMouseDragged, point: point)
            return
        }

        guard distance(from: downPoint, to: point) > tapMoveTolerance else {
            return
        }

        postMouse(type: .leftMouseDown, point: downPoint)
        touchInputState.isMouseDown = true
        postMouse(type: .leftMouseDragged, point: point)
    }

    private func handleTapCandidate(_ point: CGPoint) {
        guard let downPoint = touchInputState.pendingDownPoint,
              let downTime = touchInputState.pendingDownTime else {
            return
        }

        let duration = Date().timeIntervalSince(downTime)
        guard duration <= tapMaxDuration,
              distance(from: downPoint, to: point) <= tapMoveTolerance else {
            return
        }

        if let lastPoint = touchInputState.lastTapPoint,
           let lastTime = touchInputState.lastTapTime,
           Date().timeIntervalSince(lastTime) <= doubleTapInterval,
           distance(from: lastPoint, to: point) <= doubleTapTolerance {
            postClick(button: .left, point: point)
            touchInputState.lastTapPoint = nil
            touchInputState.lastTapTime = nil
        } else {
            touchInputState.lastTapPoint = point
            touchInputState.lastTapTime = Date()
        }
    }

    private func handleLongPress(_ point: CGPoint) {
        guard let downPoint = touchInputState.pendingDownPoint,
              !touchInputState.isMouseDown,
              !touchInputState.longPressFired,
              distance(from: downPoint, to: point) <= doubleTapTolerance else {
            return
        }

        moveCursor(to: point)
        postClick(button: .right, point: point)
        touchInputState.longPressFired = true
        touchInputState.lastTapPoint = nil
        touchInputState.lastTapTime = nil
    }

    private func clearPendingSingleTouch() {
        touchInputState.pendingDownPoint = nil
        touchInputState.pendingDownTime = nil
        touchInputState.longPressFired = false
    }

    private func handleTwoFingerTouch(_ message: TouchInputMessage, point: CGPoint) {
        switch message.action {
        case "down", "pointer_down":
            touchInputState.lastScrollPoint = point
            touchInputState.lastPinchSpan = message.span
        case "move":
            if let previous = touchInputState.lastScrollPoint {
                postScroll(from: previous, to: point)
            }
            touchInputState.lastScrollPoint = point
            touchInputState.lastPinchSpan = message.span
        case "up", "cancel", "pointer_up":
            touchInputState.lastScrollPoint = nil
            touchInputState.lastPinchSpan = nil
        default:
            break
        }
    }

    private func displayPoint(normalizedX: CGFloat, normalizedY: CGFloat, displayID: CGDirectDisplayID) -> CGPoint {
        let bounds = CGDisplayBounds(displayID)
        return CGPoint(
            x: bounds.minX + normalizedX * bounds.width,
            y: bounds.minY + normalizedY * bounds.height
        )
    }

    private func moveCursor(to point: CGPoint) {
        emitInput([
            "kind": "move",
            "x": point.x,
            "y": point.y
        ])
    }

    private func postClick(button: CGMouseButton, point: CGPoint) {
        let downType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        postMouse(type: downType, point: point, button: button)
        Thread.sleep(forTimeInterval: 0.025)
        postMouse(type: upType, point: point, button: button)
    }

    private func postMouse(type: CGEventType, point: CGPoint, button: CGMouseButton = .left) {
        emitInput([
            "kind": "mouse",
            "event": mouseEventName(for: type),
            "button": button == .right ? "right" : "left",
            "x": point.x,
            "y": point.y
        ])
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func mouseEventName(for type: CGEventType) -> String {
        switch type {
        case .leftMouseDown:
            return "leftDown"
        case .leftMouseUp:
            return "leftUp"
        case .leftMouseDragged:
            return "leftDragged"
        case .rightMouseDown:
            return "rightDown"
        case .rightMouseUp:
            return "rightUp"
        case .rightMouseDragged:
            return "rightDragged"
        case .mouseMoved:
            return "moved"
        default:
            return "moved"
        }
    }

    private func emitInput(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        print("input:\(json)")
        fflush(stdout)
    }

    private func postScroll(from previous: CGPoint, to current: CGPoint) {
        let deltaX = previous.x - current.x
        let deltaY = previous.y - current.y
        let gain: CGFloat = 1.35
        let wheelX = Int32((deltaX * gain).rounded())
        let wheelY = Int32((deltaY * gain).rounded())
        guard wheelX != 0 || wheelY != 0 else { return }

        emitInput([
            "kind": "scroll",
            "wheelX": wheelX,
            "wheelY": wheelY
        ])
    }

    private func releaseMouseIfNeeded(displayID: CGDirectDisplayID) {
        guard touchInputState.isMouseDown else { return }
        let bounds = CGDisplayBounds(displayID)
        let point = CGPoint(x: bounds.midX, y: bounds.midY)
        postMouse(type: .leftMouseUp, point: point)
        touchInputState.isMouseDown = false
    }

    private func currentServerFD() -> Int32 {
        stateLock.lock(); defer { stateLock.unlock() }
        return inputServerFD
    }

    private func setClientFD(_ fd: Int32) {
        stateLock.lock(); inputClientFD = fd; stateLock.unlock()
    }

    private func clearClientFD(ifMatching fd: Int32) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard inputClientFD == fd else { return false }
        inputClientFD = -1
        return true
    }

    func stop() {
        stateLock.lock()
        running = false
        let clientFD = inputClientFD
        let serverFD = inputServerFD
        inputClientFD = -1
        inputServerFD = -1
        let finished = threadFinished
        stateLock.unlock()
        if clientFD >= 0 {
            Darwin.shutdown(clientFD, SHUT_RDWR)
            Darwin.close(clientFD)
        }
        if serverFD >= 0 {
            Darwin.shutdown(serverFD, SHUT_RDWR)
            Darwin.close(serverFD)
        }
        finished?.wait()
        stateLock.lock()
        inputThread = nil
        threadFinished = nil
        stateLock.unlock()
    }

    private func configureNoSigpipe(_ fd: Int32) {
        var value: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout<Int32>.size))
    }

    private func status(_ message: String) {
        workerStatus(message)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
