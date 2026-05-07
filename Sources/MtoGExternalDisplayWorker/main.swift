import AppKit
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum WorkerError: Error, LocalizedError {
    case adbNotFound
    case adbFailed(String)
    case deviceMissing
    case virtualDisplayUnavailable
    case virtualDisplayCreateFailed
    case displayIdUnavailable
    case socketConnectFailed(String)
    case socketListenFailed(String)
    case streamDisconnected

    var errorDescription: String? {
        switch self {
        case .adbNotFound:
            return "adb binary not found"
        case .adbFailed(let reason):
            return "adb failed: \(reason)"
        case .deviceMissing:
            return "No authorized Android device found"
        case .virtualDisplayUnavailable:
            return "macOS virtual display API is unavailable"
        case .virtualDisplayCreateFailed:
            return "Could not create the Galaxy virtual display"
        case .displayIdUnavailable:
            return "Virtual display did not publish a display ID"
        case .socketConnectFailed(let reason):
            return "Could not open Galaxy display stream: \(reason)"
        case .socketListenFailed(let reason):
            return "Could not open Galaxy touch input server: \(reason)"
        case .streamDisconnected:
            return "Galaxy display stream disconnected"
        }
    }
}

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

private final class ExternalDisplayWorker: @unchecked Sendable {
    private let port: UInt16 = 46002
    private let inputPort: UInt16 = 46003
    private let targetFrameInterval: TimeInterval = 1.0 / 12.0
    private let maxJPEGBytes = 8 * 1_024 * 1_024
    private let cursorTargetHeight: CGFloat = 26
    private let tapMoveTolerance: CGFloat = 12
    private let doubleTapTolerance: CGFloat = 42
    private let tapMaxDuration: TimeInterval = 0.35
    private let doubleTapInterval: TimeInterval = 0.48

    private var virtualDisplay: NSObject?
    private var socketFD: Int32 = -1
    private var inputServerFD: Int32 = -1
    private var inputClientFD: Int32 = -1
    private var keepRunning = true
    private var terminationSignalSource: DispatchSourceSignal?
    private var touchInputState = TouchInputState()

    func run() -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        installTerminationSignalHandler()

        do {
            status("Starting Galaxy external display receiver")
            try startExternalDisplayReceiver()
            status("Creating isolated Mac virtual monitor")
            let displayID = try createVirtualDisplay()
            try startTouchInputServer(displayID: displayID)
            status("Opening isolated display stream")
            socketFD = try connectSocketWithRetry(timeoutSeconds: 6)
            try sendHandshake()
            status("Galaxy external display running at 1920x1200")
            streamLoop(displayID: displayID)
            cleanup()
            return 0
        } catch {
            cleanup()
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            fputs("error:\(message)\n", stderr)
            return 2
        }
    }

    private func installTerminationSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: DispatchQueue.global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            self?.keepRunning = false
        }
        terminationSignalSource = source
        source.resume()
    }

    private func createVirtualDisplay() throws -> CGDirectDisplayID {
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let displayClass = NSClassFromString("CGVirtualDisplay"),
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type else {
            throw WorkerError.virtualDisplayUnavailable
        }

        let descriptor = descriptorClass.init()
        descriptor.setValue(505, forKey: "vendorID")
        descriptor.setValue(46002, forKey: "productID")
        descriptor.setValue(930011, forKey: "serialNum")
        descriptor.setValue(930011, forKey: "serialNumber")
        descriptor.setValue("MtoG Galaxy Tab", forKey: "name")
        descriptor.setValue(1920, forKey: "maxPixelsWide")
        descriptor.setValue(1200, forKey: "maxPixelsHigh")
        descriptor.setValue(NSValue(size: CGSize(width: 325, height: 203)), forKey: "sizeInMillimeters")
        descriptor.setValue(NSValue(point: CGPoint(x: 0.3125, y: 0.3291)), forKey: "whitePoint")
        descriptor.setValue(NSValue(point: CGPoint(x: 0.1494, y: 0.0557)), forKey: "bluePrimary")
        descriptor.setValue(NSValue(point: CGPoint(x: 0.2559, y: 0.6983)), forKey: "greenPrimary")
        descriptor.setValue(NSValue(point: CGPoint(x: 0.6797, y: 0.3203)), forKey: "redPrimary")
        descriptor.setValue(DispatchQueue.global(qos: .userInitiated), forKey: "queue")

        let displayObject = try instantiateVirtualDisplay(displayClass: displayClass, descriptor: descriptor)
        virtualDisplay = displayObject

        let settings = settingsClass.init()
        let mode = modeClass.init()
        mode.setValue(1920, forKey: "width")
        mode.setValue(1200, forKey: "height")
        mode.setValue(60.0, forKey: "refreshRate")
        settings.setValue([mode], forKey: "modes")
        settings.setValue(0, forKey: "rotation")
        settings.setValue(0, forKey: "hiDPI")

        if !applySettings(display: displayObject, settings: settings) {
            status("macOS kept fallback external display settings")
        }

        guard let displayNumber = displayObject.value(forKey: "displayID") as? NSNumber,
              displayNumber.uint32Value != 0 else {
            throw WorkerError.displayIdUnavailable
        }

        return CGDirectDisplayID(displayNumber.uint32Value)
    }

    private func instantiateVirtualDisplay(displayClass: AnyClass, descriptor: NSObject) throws -> NSObject {
        let classObject: AnyObject = displayClass
        guard let allocated = classObject.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let method = class_getInstanceMethod(displayClass, NSSelectorFromString("initWithDescriptor:")) else {
            throw WorkerError.virtualDisplayCreateFailed
        }

        typealias InitWithDescriptor = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject?
        let implementation = method_getImplementation(method)
        let function = unsafeBitCast(implementation, to: InitWithDescriptor.self)
        guard let display = function(allocated, NSSelectorFromString("initWithDescriptor:"), descriptor) as? NSObject else {
            throw WorkerError.virtualDisplayCreateFailed
        }
        return display
    }

    private func applySettings(display: NSObject, settings: NSObject) -> Bool {
        guard let method = class_getInstanceMethod(type(of: display), NSSelectorFromString("applySettings:")) else {
            return false
        }

        typealias ApplySettings = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        let implementation = method_getImplementation(method)
        let function = unsafeBitCast(implementation, to: ApplySettings.self)
        return function(display, NSSelectorFromString("applySettings:"), settings)
    }

    private func connectSocketWithRetry(timeoutSeconds: TimeInterval) throws -> Int32 {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastReason = "timeout"
        repeat {
            do {
                return try connectSocket()
            } catch {
                lastReason = error.localizedDescription
                Thread.sleep(forTimeInterval: 0.18)
            }
        } while Date() < deadline

        throw WorkerError.socketConnectFailed(lastReason)
    }

    private func connectSocket() throws -> Int32 {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw WorkerError.socketConnectFailed(String(cString: strerror(errno)))
        }
        configureNoSigpipe(fd)

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard result == 0 else {
            let reason = String(cString: strerror(errno))
            Darwin.close(fd)
            throw WorkerError.socketConnectFailed(reason)
        }
        return fd
    }

    private func configureNoSigpipe(_ fd: Int32) {
        var value: Int32 = 1
        setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &value,
            socklen_t(MemoryLayout<Int32>.size)
        )
    }

    private func sendHandshake() throws {
        guard send(Data("MTOGVD1\n".utf8)) else {
            throw WorkerError.streamDisconnected
        }
    }

    private func streamLoop(displayID: CGDirectDisplayID) {
        var frameCounter = 0
        while keepRunning {
            let frameStart = Date()
            autoreleasepool {
                guard let image = CGDisplayCreateImage(displayID),
                      let compositedImage = imageWithCursorOverlay(from: image, displayID: displayID),
                      let jpeg = jpegData(from: compositedImage),
                      jpeg.count <= maxJPEGBytes else {
                    status("Waiting for screen capture permission or frame data")
                    return
                }

                if sendFrame(jpeg) {
                    frameCounter += 1
                    if frameCounter % 36 == 0 {
                        status("Galaxy external display streaming")
                    }
                } else {
                    keepRunning = false
                    status("Galaxy external display stream disconnected")
                }
            }

            let elapsed = Date().timeIntervalSince(frameStart)
            if elapsed < targetFrameInterval {
                Thread.sleep(forTimeInterval: targetFrameInterval - elapsed)
            }
        }
    }

    private func imageWithCursorOverlay(from image: CGImage, displayID: CGDirectDisplayID) -> CGImage? {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: imageRect)

        if let cursorPosition = cursorPosition(in: image, displayID: displayID) {
            drawCursor(in: context, at: cursorPosition)
        }

        return context.makeImage()
    }

    private func cursorPosition(in image: CGImage, displayID: CGDirectDisplayID) -> CGPoint? {
        guard let mouseLocation = CGEvent(source: nil)?.location else { return nil }
        let displayBounds = CGDisplayBounds(displayID)
        guard displayBounds.contains(mouseLocation) else { return nil }

        let scaleX = CGFloat(image.width) / max(displayBounds.width, 1)
        let scaleY = CGFloat(image.height) / max(displayBounds.height, 1)
        let x = (mouseLocation.x - displayBounds.minX) * scaleX
        let yFromTop = (mouseLocation.y - displayBounds.minY) * scaleY
        let y = CGFloat(image.height) - yFromTop
        return CGPoint(x: x, y: y)
    }

    private func drawCursor(in context: CGContext, at tip: CGPoint) {
        let cursor = NSCursor.arrow
        var proposedRect = CGRect(origin: .zero, size: cursor.image.size)
        guard let cursorImage = cursor.image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            drawFallbackCursor(in: context, at: tip)
            return
        }

        let imageSize = CGSize(width: cursorImage.width, height: cursorImage.height)
        let aspectRatio = imageSize.width / max(imageSize.height, 1)
        let targetSize = CGSize(width: cursorTargetHeight * aspectRatio, height: cursorTargetHeight)
        let scaleX = targetSize.width / max(cursor.image.size.width, 1)
        let scaleY = targetSize.height / max(cursor.image.size.height, 1)
        let hotSpot = cursor.hotSpot

        let drawOrigin = CGPoint(
            x: tip.x - hotSpot.x * scaleX,
            y: tip.y - targetSize.height + hotSpot.y * scaleY
        )

        context.saveGState()
        context.interpolationQuality = .high
        context.draw(cursorImage, in: CGRect(origin: drawOrigin, size: targetSize))
        context.restoreGState()
    }

    private func drawFallbackCursor(in context: CGContext, at tip: CGPoint) {
        let cursorSize = CGSize(width: 18, height: 26)

        let path = CGMutablePath()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x, y: tip.y - cursorSize.height))
        path.addLine(to: CGPoint(x: tip.x + 6, y: tip.y - 20))
        path.addLine(to: CGPoint(x: tip.x + 10, y: tip.y - cursorSize.height))
        path.addLine(to: CGPoint(x: tip.x + 15, y: tip.y - 24))
        path.addLine(to: CGPoint(x: tip.x + 11, y: tip.y - 18))
        path.addLine(to: CGPoint(x: tip.x + cursorSize.width, y: tip.y - 18))
        path.closeSubpath()

        context.saveGState()
        context.addPath(path)
        context.setFillColor(NSColor.white.cgColor)
        context.fillPath()

        context.addPath(path)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(2.2)
        context.setLineJoin(.round)
        context.strokePath()

        context.restoreGState()
    }

    private func jpegData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options = [
            kCGImageDestinationLossyCompressionQuality: 0.62
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    private func sendFrame(_ jpeg: Data) -> Bool {
        var header = Data("FRAM".utf8)
        var length = UInt32(jpeg.count).bigEndian
        withUnsafeBytes(of: &length) { header.append(contentsOf: $0) }
        return send(header) && send(jpeg)
    }

    private func send(_ data: Data) -> Bool {
        guard socketFD >= 0 else { return false }
        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return false
            }

            var sent = 0
            while sent < data.count {
                let result = Darwin.send(socketFD, baseAddress.advanced(by: sent), data.count - sent, 0)
                if result < 0 && errno == EINTR {
                    continue
                }
                if result <= 0 {
                    return false
                }
                sent += result
            }
            return true
        }
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
        Thread.detachNewThread { [weak self] in
            self?.touchInputAcceptLoop(displayID: displayID)
        }
    }

    private func touchInputAcceptLoop(displayID: CGDirectDisplayID) {
        while keepRunning {
            var clientAddress = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.accept(inputServerFD, sockaddrPointer, &length)
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

            configureNoSigpipe(clientFD)
            inputClientFD = clientFD
            status("Galaxy touch input connected")
            receiveTouchInput(clientFD: clientFD, displayID: displayID)
            releaseMouseIfNeeded(displayID: displayID)
            if inputClientFD == clientFD {
                Darwin.shutdown(clientFD, SHUT_RDWR)
                Darwin.close(clientFD)
                inputClientFD = -1
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

    private func startExternalDisplayReceiver() throws {
        let adb = try resolveADBPath()
        _ = try run(adb: adb, arguments: ["start-server"])
        try validateDevicePresence(adb: adb)
        _ = try? run(adb: adb, arguments: ["forward", "--remove", "tcp:\(port)"])
        _ = try run(adb: adb, arguments: ["forward", "tcp:\(port)", "tcp:\(port)"])
        _ = try? run(adb: adb, arguments: ["reverse", "--remove", "tcp:\(inputPort)"])
        _ = try run(adb: adb, arguments: ["reverse", "tcp:\(inputPort)", "tcp:\(inputPort)"])
        let output = try run(
            adb: adb,
            arguments: [
                "shell",
                "am",
                "start",
                "-W",
                "-n",
                "com.mtog.app/.ExternalDisplayActivity",
                "--ei",
                "port",
                "\(port)",
                "--ei",
                "inputPort",
                "\(inputPort)"
            ]
        )
        if output.contains("Error") || output.contains("Exception") {
            throw WorkerError.adbFailed(output)
        }
    }

    private func validateDevicePresence(adb: String) throws {
        let output = try run(adb: adb, arguments: ["devices"])
        let hasDevice = output
            .split(separator: "\n")
            .contains { $0.contains("\tdevice") }
        if !hasDevice {
            throw WorkerError.deviceMissing
        }
    }

    private func resolveADBPath() throws -> String {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let environment = ProcessInfo.processInfo.environment
        let candidates = [
            environment["ADB_PATH"],
            environment["ANDROID_SDK_ROOT"].flatMap { "\($0)/platform-tools/adb" },
            environment["ANDROID_HOME"].flatMap { "\($0)/platform-tools/adb" },
            "\(homeDirectory)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ].compactMap { $0 }

        for candidate in candidates {
            let expanded = NSString(string: candidate).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }

        throw WorkerError.adbNotFound
    }

    @discardableResult
    private func run(adb: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw WorkerError.adbFailed(err.isEmpty ? out : err)
        }

        return out
    }

    private func cleanup() {
        if socketFD >= 0 {
            Darwin.shutdown(socketFD, SHUT_RDWR)
            Darwin.close(socketFD)
            socketFD = -1
        }
        if inputClientFD >= 0 {
            Darwin.shutdown(inputClientFD, SHUT_RDWR)
            Darwin.close(inputClientFD)
            inputClientFD = -1
        }
        if inputServerFD >= 0 {
            Darwin.shutdown(inputServerFD, SHUT_RDWR)
            Darwin.close(inputServerFD)
            inputServerFD = -1
        }
        virtualDisplay = nil
        if let adb = try? resolveADBPath() {
            _ = try? run(adb: adb, arguments: ["forward", "--remove", "tcp:\(port)"])
            _ = try? run(adb: adb, arguments: ["reverse", "--remove", "tcp:\(inputPort)"])
        }
    }

    private func status(_ message: String) {
        print("status:\(message)")
        fflush(stdout)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private let worker = ExternalDisplayWorker()
Foundation.exit(worker.run())
