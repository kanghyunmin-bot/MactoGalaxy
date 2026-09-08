import CoreGraphics
import Darwin
import Foundation

private struct TouchInputMessage {
    let sequence: UInt64
    let kind: String
    let x: CGFloat?
    let y: CGFloat?
    let deltaX: CGFloat?
    let deltaY: CGFloat?
    let button: String?
    let tapCount: Int?
}

private struct TouchInputState {
    var highestSequence: UInt64 = 0
    var isMouseDown = false
    var lastMousePoint: CGPoint?
}

final class TouchInputServer: @unchecked Sendable {
    private let inputPort: UInt16
    private let controlSessionID: UUID
    private let stateLock = NSLock()
    private var inputServerFD: Int32 = -1
    private var inputClientFD: Int32 = -1
    private var running = true
    private var inputThread: Thread?
    private var threadFinished: DispatchSemaphore?
    private var touchInputState = TouchInputState()

    init(port: UInt16, controlSessionID: UUID) {
        inputPort = port
        self.controlSessionID = controlSessionID
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
              (object["type"] as? String) == "gestureCommand",
              let sessionValue = object["sessionId"] as? String,
              UUID(uuidString: sessionValue) == controlSessionID,
              let sequence = uint64(object["sequence"]),
              sequence > touchInputState.highestSequence,
              let kind = object["kind"] as? String else {
            return
        }

        let message = TouchInputMessage(
            sequence: sequence,
            kind: kind,
            x: number(object["x"]).map { CGFloat($0) },
            y: number(object["y"]).map { CGFloat($0) },
            deltaX: number(object["deltaX"]).map { CGFloat($0) },
            deltaY: number(object["deltaY"]).map { CGFloat($0) },
            button: object["button"] as? String,
            tapCount: integer(object["tapCount"])
        )
        guard isValid(message) else { return }
        touchInputState.highestSequence = sequence
        handleTouchInput(message, displayID: displayID)
    }

    private func uint64(_ value: Any?) -> UInt64? {
        guard let number = value as? NSNumber else { return nil }
        let result = number.uint64Value
        return result > 0 && NSNumber(value: result) == number ? result : nil
    }

    private func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let result = number.intValue
        return NSNumber(value: result) == number ? result : nil
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
        switch message.kind {
        case "click":
            guard let point = displayPoint(for: message, displayID: displayID) else { return }
            let button: CGMouseButton = message.button == "right" ? .right : .left
            moveCursor(to: point)
            postClick(button: button, point: point, tapCount: message.tapCount ?? 1)
        case "buttonDown":
            guard !touchInputState.isMouseDown,
                  let point = displayPoint(for: message, displayID: displayID) else { return }
            moveCursor(to: point)
            postMouse(type: .leftMouseDown, point: point)
            touchInputState.isMouseDown = true
            touchInputState.lastMousePoint = point
        case "drag":
            guard touchInputState.isMouseDown,
                  let point = displayPoint(for: message, displayID: displayID) else { return }
            postMouse(type: .leftMouseDragged, point: point)
            touchInputState.lastMousePoint = point
        case "buttonUp":
            guard touchInputState.isMouseDown,
                  let point = displayPoint(for: message, displayID: displayID) else { return }
            postMouse(type: .leftMouseUp, point: point)
            touchInputState.isMouseDown = false
            touchInputState.lastMousePoint = point
        case "scroll":
            let bounds = CGDisplayBounds(displayID)
            let deltaX = (message.deltaX ?? 0) * bounds.width
            let deltaY = (message.deltaY ?? 0) * bounds.height
            postScroll(deltaX: deltaX, deltaY: deltaY)
        default:
            break
        }
    }

    private func isValid(_ message: TouchInputMessage) -> Bool {
        let validPoint = message.x.map { $0.isFinite && (0 ... 1).contains($0) } == true &&
            message.y.map { $0.isFinite && (0 ... 1).contains($0) } == true
        switch message.kind {
        case "click":
            return validPoint && ["left", "right"].contains(message.button ?? "") &&
                (1 ... 2).contains(message.tapCount ?? 0)
        case "buttonDown", "drag", "buttonUp":
            return validPoint && message.button == "left"
        case "scroll":
            guard let deltaX = message.deltaX, let deltaY = message.deltaY else { return false }
            return deltaX.isFinite && deltaY.isFinite && abs(deltaX) <= 1 && abs(deltaY) <= 1
        default:
            return false
        }
    }

    private func displayPoint(for message: TouchInputMessage, displayID: CGDirectDisplayID) -> CGPoint? {
        guard let x = message.x, let y = message.y else { return nil }
        return displayPoint(
            normalizedX: x.clamped(to: 0 ... 1),
            normalizedY: y.clamped(to: 0 ... 1),
            displayID: displayID
        )
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

    private func postClick(button: CGMouseButton, point: CGPoint, tapCount: Int) {
        let downType: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        for clickState in 1 ... tapCount {
            postMouse(type: downType, point: point, button: button, clickState: clickState)
            Thread.sleep(forTimeInterval: 0.025)
            postMouse(type: upType, point: point, button: button, clickState: clickState)
        }
    }

    private func postMouse(
        type: CGEventType,
        point: CGPoint,
        button: CGMouseButton = .left,
        clickState: Int = 0
    ) {
        emitInput([
            "kind": "mouse",
            "event": mouseEventName(for: type),
            "button": button == .right ? "right" : "left",
            "clickState": clickState,
            "x": point.x,
            "y": point.y
        ])
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

    private func postScroll(deltaX: CGFloat, deltaY: CGFloat) {
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
        let point = touchInputState.lastMousePoint ?? CGPoint(x: bounds.midX, y: bounds.midY)
        postMouse(type: .leftMouseUp, point: point)
        touchInputState.isMouseDown = false
        touchInputState.lastMousePoint = point
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
        _ = finished?.wait(timeout: .now() + 2)
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
