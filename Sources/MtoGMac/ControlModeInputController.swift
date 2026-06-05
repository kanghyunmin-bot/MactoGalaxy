import AppKit
import ApplicationServices
import Foundation

final class ControlModeInputController: @unchecked Sendable {
    private enum HapticIntent {
        case modeEnter
        case modeExit
        case primaryClick
        case secondaryClick
        case pinchStep
        case edgeReturn

        var pattern: NSHapticFeedbackManager.FeedbackPattern {
            switch self {
            case .modeEnter, .modeExit, .edgeReturn:
                return .alignment
            case .pinchStep:
                return .levelChange
            case .primaryClick, .secondaryClick:
                return .generic
            }
        }
    }

    private let stateQueueKey = DispatchSpecificKey<Void>()
    private let sessionClient: SessionClient
    private let commandChannel: ADBCommandChannel
    private let hidBridge: AoaHidBridge
    private let stateQueue = DispatchQueue(label: "com.mtog.control-mode-state", qos: .userInitiated)

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var flushTimer: DispatchSourceTimer?
    private var globalGestureMonitor: Any?
    private var localGestureMonitor: Any?
    private var gestureCaptureOverlay: GestureCaptureOverlay?
    private var previouslyFrontmostApplication: NSRunningApplication?

    private var isActive = false
    private var displaySize = CGSize(width: 1848, height: 2960)
    private var hasSessionDisplayMetrics = false
    private var cursorPoint = CGPoint(x: 924, y: 1480)
    private var pointerGain: CGFloat = ControlInputTuningProfile.standard.pointerGain
    private var scrollGain: Double = ControlInputTuningProfile.standard.scrollGain
    private var pinchGain: Double = ControlInputTuningProfile.standard.pinchGain
    private var swipeGestureEnabled = ControlInputTuningProfile.standard.swipeEnabled
    private var pinchGestureEnabled = ControlInputTuningProfile.standard.pinchEnabled
    private var hapticsEnabled = ControlInputTuningProfile.standard.hapticsEnabled
    private var primaryButtonDown = false
    private var moveDirty = false
    private var scrollAccumulatorX: Double = 0
    private var scrollAccumulatorY: Double = 0
    private var hidMouseAccumulatorX: Double = 0
    private var hidMouseAccumulatorY: Double = 0
    private var hidScrollAccumulatorY: Double = 0
    private var scrollTouchStreamActive = false
    private var scrollTouchPoint = CGPoint.zero
    private var lastScrollInputAt = Date.distantPast
    private var cursorHidden = false
    private var parkedCursorLocation = CGPoint.zero
    private var exitPending = false
    private var returnCornerEnteredAt: Date?
    private var touchStreamActive = false
    private var pendingClickOrigin: CGPoint?
    private var pendingTextBuffer = ""
    private var pendingTextFlushAt = Date.distantPast
    private var lastMagnifyAt = Date.distantPast
    private var lastScrollDispatchAt = Date.distantPast
    private var lastHidMouseDispatchAt = Date.distantPast
    private var lastHidScrollDispatchAt = Date.distantPast
    private var pendingMagnification: Double = 0
    private var lastHapticAtByIntent: [HapticIntent: Date] = [:]
    private let dragActivationDistance: CGFloat = 10
    private let hidPointerGainMultiplier: CGFloat = 0.32
    private let hidScrollGainMultiplier: Double = 0.10
    private let allowAccessibilityFallbackInput = false

    var statusHandler: ((String) -> Void)?
    var exitHandler: (() -> Void)?

    init(
        sessionClient: SessionClient,
        commandChannel: ADBCommandChannel = ADBCommandChannel(),
        hidBridge: AoaHidBridge = AoaHidBridge()
    ) {
        self.sessionClient = sessionClient
        self.commandChannel = commandChannel
        self.hidBridge = hidBridge
        self.stateQueue.setSpecific(key: stateQueueKey, value: ())
        self.commandChannel.errorHandler = { [weak self] message in
            self?.statusHandler?(message)
        }
    }

    func updateTuningProfile(_ profile: ControlInputTuningProfile) {
        stateQueue.async {
            self.pointerGain = profile.pointerGain
            self.scrollGain = profile.scrollGain
            self.pinchGain = profile.pinchGain
            self.swipeGestureEnabled = profile.swipeEnabled
            self.pinchGestureEnabled = profile.pinchEnabled
            self.hapticsEnabled = profile.hapticsEnabled
        }
    }

    func updateRemoteDisplaySize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        stateQueue.async {
            self.displaySize = size
            self.hasSessionDisplayMetrics = true
        }
    }

    func activate(trigger: ControlCorner, initialPointerLocation: CGPoint) {
        let nativeHidInput = usesNativeHidInput()
        guard nativeHidInput || allowAccessibilityFallbackInput else {
            statusHandler?("Android 제어 모드는 네이티브 HID만 사용합니다. USB에서는 USB HID를 먼저 켜고, 무선 조작은 미러링 창 안에서 사용하세요.")
            return
        }

        if !nativeHidInput {
            guard requestMacInputAccessIfNeeded() else {
                statusHandler?("macOS 접근성 권한이 필요합니다. 시스템 설정에서 MtoG를 허용하세요.")
                return
            }
            commandChannel.activate()
            if !stateQueue.sync(execute: { hasSessionDisplayMetrics }),
               let queriedDisplaySize = commandChannel.queryDisplaySize() {
                displaySize = queriedDisplaySize
            }
        }

        guard requestMacListenEventAccessIfNeeded() else {
            statusHandler?("macOS 입력 모니터링 권한이 필요합니다. 시스템 설정 > 개인정보 보호 및 보안 > 입력 모니터링에서 MtoG를 허용한 뒤 앱을 다시 여세요.")
            return
        }

        stateQueue.sync {
            isActive = true
            exitPending = false
            returnCornerEnteredAt = nil
            configureInitialCursor(trigger: trigger, mouseLocation: initialPointerLocation)
            parkedCursorLocation = parkingLocation(for: screenFrame(containing: initialPointerLocation), entryCorner: trigger)
        }

        installEventTapIfNeeded()
        presentGestureCaptureOverlay(for: screenFrame(containing: initialPointerLocation))
        startFlushTimerIfNeeded()
        setCursorHidden(true)
        parkCursor()

        stateQueue.async { [weak self] in
            self?.sendPointerOverlayUpdate()
        }
        performHaptic(.modeEnter)
        statusHandler?("Android 제어 모드: Mac 입력을 Android 네이티브 HID 마우스/키보드로 전송 중")
    }

    private func usesNativeHidInput() -> Bool {
        hidBridge.isRunning
    }

    func deactivate() {
        var touchReleasePoint: CGPoint?
        var pendingTextToSend: String?
        stateQueue.sync {
            guard isActive else { return }
            if touchStreamActive {
                touchReleasePoint = normalizedRemotePoint(for: cursorPoint)
            } else if scrollTouchStreamActive {
                touchReleasePoint = normalizedRemotePoint(for: scrollTouchPoint)
            }
            primaryButtonDown = false
            touchStreamActive = false
            scrollTouchStreamActive = false
            pendingClickOrigin = nil
            pendingTextToSend = drainPendingTextLocked(force: true)
            isActive = false
            exitPending = false
            returnCornerEnteredAt = nil
            moveDirty = false
            scrollAccumulatorX = 0
            scrollAccumulatorY = 0
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        flushTimer?.cancel()
        flushTimer = nil
        dismissGestureCaptureOverlay()
        commandChannel.deactivate()
        parkCursor()
        setCursorHidden(false)
        if let touchReleasePoint {
            Task { @MainActor [sessionClient] in
                await sessionClient.sendRemoteTouchEnd(
                    normalizedX: touchReleasePoint.x,
                    normalizedY: touchReleasePoint.y
                )
            }
        }
        if let pendingTextToSend, !pendingTextToSend.isEmpty {
            sendCommittedText(pendingTextToSend)
        }
        performHaptic(.modeExit)
        statusHandler?("Mac 제어로 복귀")
    }

    private func requestMacInputAccessIfNeeded() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func requestMacListenEventAccessIfNeeded() -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }

        _ = CGRequestListenEventAccess()
        return CGPreflightListenEventAccess()
    }

    private func installEventTapIfNeeded() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return
        }

        let events: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown,
            .leftMouseUp,
            .leftMouseDragged,
            .rightMouseDown,
            .rightMouseUp,
            .rightMouseDragged,
            .otherMouseDown,
            .otherMouseUp,
            .otherMouseDragged,
            .scrollWheel,
            .keyDown,
            .keyUp,
            .flagsChanged
        ]

        let mask = events.reduce(CGEventMask(0)) { partialResult, type in
            partialResult | (CGEventMask(1) << type.rawValue)
        }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let controller = Unmanaged<ControlModeInputController>
                .fromOpaque(refcon)
                .takeUnretainedValue()
            return controller.handleEvent(type: type, event: event)
        }

        let ref = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: ref
        ) else {
            statusHandler?("macOS 입력 캡처를 시작하지 못했습니다. 접근성/입력 모니터링 권한을 확인하세요.")
            return
        }

        self.eventTap = eventTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func installGestureMonitorsIfNeeded() {
        if globalGestureMonitor == nil {
            globalGestureMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.swipe, .magnify]) { [weak self] event in
                self?.handleGestureEvent(event)
            }
        }

        if localGestureMonitor == nil {
            localGestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.swipe, .magnify]) { [weak self] event in
                self?.handleGestureEvent(event)
                return event
            }
        }
    }

    private func startFlushTimerIfNeeded() {
        guard flushTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            self?.flushPendingInput()
        }
        timer.resume()
        flushTimer = timer
    }

    private func flushPendingInput() {
        guard isActive, !exitPending else { return }

        if usesNativeHidInput() {
            dispatchHidMouseAccumulatorIfNeeded(force: true)
            dispatchHidScrollIfNeeded(force: false)
        }

        if let pendingText = drainPendingTextLocked(force: false),
           !pendingText.isEmpty {
            sendCommittedText(pendingText)
        }

        if moveDirty {
            sendPointerOverlayUpdate()
            if primaryButtonDown && touchStreamActive {
                sendRemoteTouchMove()
            }
            moveDirty = false
        }

        dispatchTrackpadPinchIfNeeded()

        if shouldAutoReturnToMac() {
            exitPending = true
            performHaptic(.edgeReturn)
            statusHandler?("Android 좌측 하단 복귀 지점 감지, Mac으로 전환합니다.")
            DispatchQueue.main.async { [weak self] in
                self?.exitHandler?()
            }
            return
        }

        let now = Date()
        if (abs(scrollAccumulatorX) >= 1 || abs(scrollAccumulatorY) >= 1),
           now.timeIntervalSince(lastScrollDispatchAt) >= 0.03 {
            let horizontal = scrollAccumulatorX
            let vertical = scrollAccumulatorY
            scrollAccumulatorX = 0
            scrollAccumulatorY = 0
            lastScrollDispatchAt = now
            dispatchTrackpadScroll(horizontal: horizontal, vertical: vertical)
            parkCursor()
        }

        if scrollTouchStreamActive,
           now.timeIntervalSince(lastScrollInputAt) >= 0.14 {
            let releasePoint = normalizedRemotePoint(for: scrollTouchPoint)
            scrollTouchStreamActive = false
            Task { @MainActor [sessionClient] in
                await sessionClient.sendRemoteTouchEnd(
                    normalizedX: releasePoint.x,
                    normalizedY: releasePoint.y
                )
            }
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let shouldCapture = stateQueue.sync { isActive && !exitPending }
        guard shouldCapture else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            handlePointerMotion(event)
            return nil
        case .leftMouseDown:
            handleLeftMouseDown()
            return nil
        case .leftMouseUp:
            handleLeftMouseUp()
            return nil
        case .rightMouseDown:
            handleSecondaryClick()
            return nil
        case .rightMouseUp:
            return nil
        case .otherMouseDown:
            handleMiddleMouseDown()
            return nil
        case .otherMouseUp:
            handleMiddleMouseUp()
            return nil
        case .scrollWheel:
            handleScroll(event)
            return nil
        case .flagsChanged:
            handleModifierFlagsChanged(event)
            return nil
        case .keyDown:
            handleKeyDown(event)
            return nil
        case .keyUp:
            return nil
        default:
            return nil
        }
    }

    private func handlePointerMotion(_ event: CGEvent) {
        var touchStartPoint: CGPoint?
        stateQueue.sync {
            let deltaX = CGFloat(event.getDoubleValueField(.mouseEventDeltaX))
            let deltaY = CGFloat(event.getDoubleValueField(.mouseEventDeltaY))

            guard deltaX != 0 || deltaY != 0 else { return }

            cursorPoint.x = clamp(cursorPoint.x + (deltaX * pointerGain), max: displaySize.width - 1)
            cursorPoint.y = clamp(cursorPoint.y + (deltaY * pointerGain), max: displaySize.height - 1)
            if usesNativeHidInput() {
                let hidGain = max(0.28, min(0.78, pointerGain * hidPointerGainMultiplier))
                hidMouseAccumulatorX += Double(deltaX * hidGain)
                hidMouseAccumulatorY += Double(deltaY * hidGain)
                dispatchHidMouseAccumulatorIfNeeded(force: false)
                return
            }
            if primaryButtonDown,
               !touchStreamActive,
               let pendingClickOrigin,
               distanceBetween(pendingClickOrigin, cursorPoint) >= dragActivationDistance {
                touchStreamActive = true
                touchStartPoint = normalizedRemotePoint(for: pendingClickOrigin)
                self.pendingClickOrigin = nil
            }
            moveDirty = true
        }
        if let touchStartPoint {
            Task { @MainActor [sessionClient] in
                await sessionClient.sendRemoteTouchStart(
                    normalizedX: touchStartPoint.x,
                    normalizedY: touchStartPoint.y
                )
            }
        }
        parkCursor()
    }

    private func handleLeftMouseDown() {
        stateQueue.sync {
            primaryButtonDown = true
            moveDirty = false
            returnCornerEnteredAt = nil
            touchStreamActive = false
            pendingClickOrigin = cursorPoint
            sendPointerOverlayUpdate()
        }
        if usesNativeHidInput() {
            hidBridge.sendMouse(buttons: 1, dx: 0, dy: 0)
        }
        performHaptic(.primaryClick, minInterval: 0.03)
        parkCursor()
    }

    private func handleLeftMouseUp() {
        if usesNativeHidInput() {
            stateQueue.sync {
                primaryButtonDown = false
                touchStreamActive = false
                pendingClickOrigin = nil
            }
            hidBridge.sendMouse(buttons: 0, dx: 0, dy: 0)
            parkCursor()
            return
        }
        let action = stateQueue.sync { () -> (tap: CGPoint?, release: CGPoint?) in
            guard primaryButtonDown || touchStreamActive else { return (nil, nil) }
            let normalizedPoint = normalizedRemotePoint(for: cursorPoint)
            let shouldReleaseTouch = touchStreamActive
            let shouldTap = !touchStreamActive
            primaryButtonDown = false
            touchStreamActive = false
            pendingClickOrigin = nil
            sendPointerOverlayUpdate()
            return (
                shouldTap ? normalizedPoint : nil,
                shouldReleaseTouch ? normalizedPoint : nil
            )
        }
        if let normalizedTapPoint = action.tap {
            Task { @MainActor [sessionClient] in
                await sessionClient.sendRemoteTap(
                    normalizedX: normalizedTapPoint.x,
                    normalizedY: normalizedTapPoint.y
                )
            }
        }
        if let normalizedReleasePoint = action.release {
            Task { @MainActor [sessionClient] in
                await sessionClient.sendRemoteTouchEnd(
                    normalizedX: normalizedReleasePoint.x,
                    normalizedY: normalizedReleasePoint.y
                )
            }
        }
        parkCursor()
    }

    private func sendRemoteTouchMove() {
        let normalizedPoint = normalizedRemotePoint(for: cursorPoint)
        Task { @MainActor [sessionClient] in
            await sessionClient.sendRemoteTouchMove(
                normalizedX: normalizedPoint.x,
                normalizedY: normalizedPoint.y
            )
        }
    }

    private func handleSecondaryClick() {
        if usesNativeHidInput() {
            performHaptic(.secondaryClick)
            hidBridge.sendMouse(buttons: 2, dx: 0, dy: 0)
            hidBridge.sendMouse(buttons: 0, dx: 0, dy: 0)
            statusHandler?("보조 클릭을 USB HID 오른쪽 클릭으로 전송")
            return
        }
        let point = stateQueue.sync { normalizedRemotePoint(for: cursorPoint) }
        performHaptic(.secondaryClick)
        Task { @MainActor [sessionClient] in
            await sessionClient.sendRemoteGesture(
                kind: "contextPress",
                startX: point.x,
                startY: point.y,
                endX: point.x,
                endY: point.y,
                durationMs: 520
            )
        }
        statusHandler?("보조 클릭을 Android 컨텍스트 long press로 전송")
    }

    private func handleMiddleMouseDown() {
        guard usesNativeHidInput() else { return }
        hidBridge.sendMouse(buttons: 4, dx: 0, dy: 0)
    }

    private func handleMiddleMouseUp() {
        guard usesNativeHidInput() else { return }
        hidBridge.sendMouse(buttons: 0, dx: 0, dy: 0)
    }

    private func handleScroll(_ event: CGEvent) {
        if usesNativeHidInput() {
            let pointDeltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let lineDeltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let raw = pointDeltaY != 0 ? pointDeltaY : (lineDeltaY * 12.0)
            stateQueue.sync {
                hidScrollAccumulatorY += raw * max(0.06, min(0.18, scrollGain * hidScrollGainMultiplier))
                dispatchHidScrollIfNeeded(force: false)
            }
            parkCursor()
            return
        }
        stateQueue.sync {
            let pointDeltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let pointDeltaX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            let lineDeltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let lineDeltaX = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
            scrollAccumulatorY += pointDeltaY != 0 ? pointDeltaY : (lineDeltaY * 12.0)
            scrollAccumulatorX += pointDeltaX != 0 ? pointDeltaX : (lineDeltaX * 12.0)
            lastScrollInputAt = Date()
        }
        parkCursor()
    }

    private func dispatchHidMouseAccumulatorIfNeeded(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastHidMouseDispatchAt) >= 0.008 else { return }
        let dx = consumeHidAxis(&hidMouseAccumulatorX, threshold: force ? 0.45 : 0.9, limit: 18)
        let dy = consumeHidAxis(&hidMouseAccumulatorY, threshold: force ? 0.45 : 0.9, limit: 18)
        guard dx != 0 || dy != 0 else { return }
        lastHidMouseDispatchAt = now
        hidBridge.sendMouse(
            buttons: primaryButtonDown ? 1 : 0,
            dx: dx,
            dy: dy
        )
        parkCursor()
    }

    private func dispatchHidScrollIfNeeded(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastHidScrollDispatchAt) >= 0.045 else { return }
        let wheel = consumeHidAxis(&hidScrollAccumulatorY, threshold: force ? 0.7 : 1.0, limit: 1)
        guard wheel != 0 else { return }
        lastHidScrollDispatchAt = now
        hidBridge.sendMouse(buttons: 0, dx: 0, dy: 0, wheel: wheel)
    }

    private func consumeHidAxis(_ value: inout Double, threshold: Double, limit: Int) -> Int {
        guard abs(value) >= threshold else { return 0 }
        let raw = value.rounded(.towardZero)
        let clamped = Int(max(Double(-limit), min(Double(limit), raw)))
        value -= Double(clamped)
        return clamped
    }

    private func handleGestureEvent(_ event: NSEvent) {
        let captureState = stateQueue.sync {
            (
                isActive && !exitPending,
                swipeGestureEnabled,
                pinchGestureEnabled
            )
        }
        guard captureState.0 else { return }

        switch event.type {
        case .swipe:
            guard captureState.1 else { return }
            let deltaX = event.deltaX
            let deltaY = event.deltaY
            guard abs(deltaX) > 0.1 || abs(deltaY) > 0.1 else { return }
            dispatchTrackpadSwipe(deltaX: deltaX, deltaY: deltaY)
        case .magnify:
            guard captureState.2 else { return }
            let magnification = event.magnification
            guard abs(magnification) > 0.004 else { return }
            stateQueue.sync {
                pendingMagnification += magnification
            }
            dispatchTrackpadPinchIfNeeded()
        default:
            return
        }
    }

    private func presentGestureCaptureOverlay(for screenFrame: CGRect) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let overlay = GestureCaptureOverlay(frame: screenFrame)
            overlay.updateHandlers(
                onMagnify: { [weak self] event in
                    self?.handleGestureEvent(event)
                },
                onMagnificationDelta: { [weak self] delta in
                    guard let self else { return }
                    let captureState = self.stateQueue.sync {
                        (self.isActive && !self.exitPending, self.pinchGestureEnabled)
                    }
                    guard captureState.0, captureState.1 else { return }
                    guard abs(delta) > 0.003 else { return }
                    self.stateQueue.sync {
                        self.pendingMagnification += delta
                    }
                    self.dispatchTrackpadPinchIfNeeded()
                },
                onSwipe: { [weak self] event in
                    self?.handleGestureEvent(event)
                },
                onSmartMagnify: { [weak self] _ in
                    let center = self?.stateQueue.sync { self?.normalizedRemotePoint(for: self?.cursorPoint ?? .zero) } ?? CGPoint(x: 0.5, y: 0.5)
                    Task { @MainActor [sessionClient = self?.sessionClient] in
                        await sessionClient?.sendRemotePinch(
                            centerX: center.x,
                            centerY: center.y,
                            magnification: 0.45
                        )
                    }
                }
            )
            self.previouslyFrontmostApplication = NSWorkspace.shared.frontmostApplication
            self.gestureCaptureOverlay = overlay
            overlay.present()
        }
    }

    private func dismissGestureCaptureOverlay() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.gestureCaptureOverlay?.dismiss()
            self.gestureCaptureOverlay = nil

            guard let app = self.previouslyFrontmostApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else {
                self.previouslyFrontmostApplication = nil
                return
            }

            self.previouslyFrontmostApplication = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                app.activate(options: [])
            }
        }
    }

    private func handleKeyDown(_ event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if isExitHotkey(keyCode: keyCode, flags: flags) {
            flushPendingText(force: true)
            DispatchQueue.main.async { [weak self] in
                self?.exitHandler?()
            }
            return
        }

        if sendHidKeyIfAvailable(keyCode: keyCode, flags: flags) {
            return
        }

        if handleModifierShortcut(flags: flags, event: event) {
            return
        }

        if handleSpecialKey(keyCode: keyCode) {
            return
        }

        guard !flags.contains(.maskCommand),
              !flags.contains(.maskControl) else {
            return
        }

        let text = unicodeText(from: event)
        guard !text.isEmpty else { return }
        sendTextInput(text)
    }

    private func handleModifierFlagsChanged(_ event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        guard keyCode == 54, flags.contains(.maskCommand) else {
            return
        }

        flushPendingText(force: true)
        if sendHidKeyIfAvailable(keyCode: keyCode, flags: flags) {
            return
        }

        if handleModifierShortcut(flags: flags, event: event) {
            return
        }
    }

    private func handleModifierShortcut(flags: CGEventFlags, event: CGEvent) -> Bool {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard let combination = MacToAndroidKeyboardTranslator.adbCombination(
            forMacKeyCode: keyCode,
            flags: flags
        ) else {
            return false
        }

        flushPendingText(force: true)
        commandChannel.sendKeyCombination(combination.keys)
        if let status = combination.status {
            statusHandler?(status)
        }
        return true
    }

    private func handleSpecialKey(keyCode: Int) -> Bool {
        switch keyCode {
        case 51, 117:
            if consumeBufferedDelete() {
                return true
            }
            sendDeleteBackward()
            return true
        case 36, 76:
            flushPendingText(force: true)
            sendEnterKey()
            return true
        case 48:
            flushPendingText(force: true)
            sendKeyEvent("TAB")
            return true
        case 49:
            sendTextInput(" ")
            return true
        case 53:
            flushPendingText(force: true)
            sendKeyEvent("ESCAPE")
            return true
        case 123:
            flushPendingText(force: true)
            sendKeyEvent("DPAD_LEFT")
            return true
        case 124:
            flushPendingText(force: true)
            sendKeyEvent("DPAD_RIGHT")
            return true
        case 125:
            flushPendingText(force: true)
            sendKeyEvent("DPAD_DOWN")
            return true
        case 126:
            flushPendingText(force: true)
            sendKeyEvent("DPAD_UP")
            return true
        default:
            return false
        }
    }

    private func sendKeyEvent(_ key: String) {
        if usesNativeHidInput() {
            return
        }
        commandChannel.sendKeyEvent(key)
    }

    private func sendHidKeyIfAvailable(keyCode: Int, flags: CGEventFlags) -> Bool {
        guard usesNativeHidInput() else {
            return false
        }

        guard let translated = MacToAndroidKeyboardTranslator.hidKey(
            forMacKeyCode: keyCode,
            flags: flags
        ) else {
            return false
        }

        hidBridge.sendKey(
            modifiers: translated.modifiers,
            usage: translated.usage
        )
        if let status = translated.status {
            statusHandler?(status)
        }
        return true
    }

    private func sendTextInput(_ text: String) {
        let standardized = standardizeHangulInput(text)
        stateQueue.sync {
            pendingTextBuffer.append(standardized)
            let bufferWindow = shouldBufferForHangulComposition(standardized) ? 0.28 : 0.06
            pendingTextFlushAt = Date().addingTimeInterval(bufferWindow)
        }
    }

    private func sendDeleteBackward() {
        flushPendingText(force: true)
        Task { @MainActor [sessionClient] in
            await sessionClient.sendRemoteDeleteBackward()
        }
    }

    private func sendEnterKey() {
        flushPendingText(force: true)
        Task { @MainActor [sessionClient] in
            await sessionClient.sendRemoteEnterKey()
        }
    }

    private func sendCommittedText(_ text: String) {
        guard !text.isEmpty else { return }
        Task { @MainActor [sessionClient] in
            await sessionClient.sendRemoteText(text)
        }
    }

    private func flushPendingText(force: Bool) {
        let textToSend = stateQueue.sync {
            drainPendingTextLocked(force: force)
        }
        if let textToSend, !textToSend.isEmpty {
            sendCommittedText(textToSend)
        }
    }

    private func consumeBufferedDelete() -> Bool {
        stateQueue.sync {
            guard !pendingTextBuffer.isEmpty else { return false }
            pendingTextBuffer.removeLast()
            pendingTextFlushAt = pendingTextBuffer.isEmpty
                ? .distantPast
                : Date().addingTimeInterval(0.28)
            return true
        }
    }

    private func drainPendingTextLocked(force: Bool) -> String? {
        guard !pendingTextBuffer.isEmpty else { return nil }
        guard force || Date() >= pendingTextFlushAt else { return nil }

        let composed = composeHangulText(pendingTextBuffer)
        pendingTextBuffer.removeAll(keepingCapacity: true)
        pendingTextFlushAt = .distantPast
        return composed
    }

    private func configureInitialCursor(trigger: ControlCorner, mouseLocation: CGPoint) {
        let normalized = normalizedPoint(for: mouseLocation)
        var initialX = displaySize.width * normalized.x
        var initialY = displaySize.height * normalized.y

        switch trigger {
        case .topLeft:
            initialX = displaySize.width * 0.02
            initialY = displaySize.height * 0.02
        case .topRight:
            initialX = displaySize.width * 0.98
            initialY = displaySize.height * 0.02
        case .bottomLeft:
            initialX = displaySize.width * 0.02
            initialY = displaySize.height * 0.98
        case .bottomRight:
            initialX = displaySize.width * 0.98
            initialY = displaySize.height * 0.98
        }

        cursorPoint = CGPoint(
            x: clamp(initialX, max: displaySize.width - 1),
            y: clamp(initialY, max: displaySize.height - 1)
        )
    }

    private func shouldAutoReturnToMac() -> Bool {
        guard !primaryButtonDown else {
            returnCornerEnteredAt = nil
            return false
        }

        let cornerSize = max(min(displaySize.width, displaySize.height) * 0.032, 44)
        let isInsideReturnCorner = cursorPoint.x <= cornerSize &&
            cursorPoint.y >= displaySize.height - cornerSize

        guard isInsideReturnCorner else {
            returnCornerEnteredAt = nil
            return false
        }

        if let enteredAt = returnCornerEnteredAt {
            return Date().timeIntervalSince(enteredAt) >= 0.22
        }

        returnCornerEnteredAt = Date()
        return false
    }

    private func sendPointerOverlayUpdate() {
        let normalizedX = Double(max(0, min(1, cursorPoint.x / max(displaySize.width, 1))))
        let normalizedY = Double(max(0, min(1, cursorPoint.y / max(displaySize.height, 1))))
        let primaryDown = primaryButtonDown
        Task { @MainActor [sessionClient] in
            await sessionClient.sendRemotePointerUpdate(
                normalizedX: normalizedX,
                normalizedY: normalizedY,
                primaryButtonDown: primaryDown
            )
        }
    }

    private func normalizedRemotePoint(for point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(1, point.x / max(displaySize.width, 1))),
            y: max(0, min(1, point.y / max(displaySize.height, 1)))
        )
    }

    private func normalizedPoint(for mouseLocation: CGPoint) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        let x = (mouseLocation.x - screen.frame.minX) / screen.frame.width
        let y = 1 - ((mouseLocation.y - screen.frame.minY) / screen.frame.height)
        return CGPoint(
            x: x.clamped(to: 0...1),
            y: y.clamped(to: 0...1)
        )
    }

    private func screenFrame(containing mouseLocation: CGPoint) -> CGRect {
        NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })?.frame
            ?? NSScreen.main?.frame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func parkingLocation(for screenFrame: CGRect, entryCorner: ControlCorner) -> CGPoint {
        let inset = max(48, CGFloat(96))
        switch entryCorner {
        case .topLeft:
            return CGPoint(x: screenFrame.minX + inset, y: screenFrame.maxY - inset)
        case .topRight:
            return CGPoint(x: screenFrame.maxX - inset, y: screenFrame.maxY - inset)
        case .bottomLeft:
            return CGPoint(x: screenFrame.minX + inset, y: screenFrame.minY + inset)
        case .bottomRight:
            return CGPoint(x: screenFrame.maxX - inset, y: screenFrame.minY + inset)
        }
    }

    private func unicodeText(from event: CGEvent) -> String {
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return "" }

        var scalars = Array<UniChar>(repeating: 0, count: length)
        event.keyboardGetUnicodeString(
            maxStringLength: length,
            actualStringLength: &length,
            unicodeString: &scalars
        )
        return String(utf16CodeUnits: scalars, count: length)
    }

    private func shouldBufferForHangulComposition(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x1100...0x11FF).contains(scalar.value) ||
            (0x3130...0x318F).contains(scalar.value) ||
            (0xA960...0xA97F).contains(scalar.value) ||
            (0xD7B0...0xD7FF).contains(scalar.value)
        }
    }

    private func standardizeHangulInput(_ text: String) -> String {
        String(text.map { Self.standardizedHangulCharacter[$0] ?? $0 })
    }

    private func composeHangulText(_ text: String) -> String {
        let scalars = Array(text)
        var index = 0
        var output = ""

        while index < scalars.count {
            let current = scalars[index]
            guard let leadIndex = Self.leadingIndex[current],
                  let vowel = parseVowel(in: scalars, from: index + 1) else {
                output.append(current)
                index += 1
                continue
            }

            var nextIndex = vowel.nextIndex
            var tailIndex = 0

            if nextIndex < scalars.count,
               let directTailIndex = Self.trailingIndex[scalars[nextIndex]] {
                if nextIndex + 1 < scalars.count,
                   let compoundTailIndex = Self.compoundTrailingIndex[
                    String([scalars[nextIndex], scalars[nextIndex + 1]])
                   ],
                   !(nextIndex + 2 < scalars.count && Self.vowelIndex[scalars[nextIndex + 2]] != nil) {
                    tailIndex = compoundTailIndex
                    nextIndex += 2
                } else if nextIndex + 1 < scalars.count,
                          Self.vowelIndex[scalars[nextIndex + 1]] != nil {
                    tailIndex = 0
                } else {
                    tailIndex = directTailIndex
                    nextIndex += 1
                }
            }

            let scalarValue = 0xAC00 + ((leadIndex * 21) + vowel.index) * 28 + tailIndex
            if let scalar = UnicodeScalar(scalarValue) {
                output.unicodeScalars.append(scalar)
            }
            index = nextIndex
        }

        return output.precomposedStringWithCanonicalMapping
    }

    private func dispatchTrackpadSwipe(deltaX: Double, deltaY: Double) {
        let travel = 0.075 * max(1.0, min(1.45, max(abs(deltaX), abs(deltaY))))
        let start = stateQueue.sync { normalizedRemotePoint(for: cursorPoint) }
        let end = CGPoint(
            x: (start.x + (deltaX * travel)).clamped(to: 0.05...0.95),
            y: (start.y - (deltaY * travel)).clamped(to: 0.05...0.95)
        )

        Task { @MainActor [sessionClient] in
            await sessionClient.sendRemoteGesture(
                kind: "swipe",
                startX: start.x,
                startY: start.y,
                endX: end.x,
                endY: end.y,
                durationMs: 260
            )
        }
        statusHandler?("트랙패드 swipe를 Android 화면 스와이프로 전송")
    }

    private func dispatchTrackpadScroll(horizontal: Double, vertical: Double) {
        guard !primaryButtonDown, !touchStreamActive else { return }

        let scaledHorizontal = horizontal * max(1.6, min(3.6, scrollGain * 2.2))
        let scaledVertical = vertical * max(1.6, min(3.8, scrollGain * 2.4))

        if !scrollTouchStreamActive {
            scrollTouchStreamActive = true
            scrollTouchPoint = cursorPoint
            let start = normalizedRemotePoint(for: scrollTouchPoint)
            Task { @MainActor [sessionClient] in
                await sessionClient.sendRemoteTouchStart(
                    normalizedX: start.x,
                    normalizedY: start.y
                )
            }
        }

        scrollTouchPoint.x = clamp(scrollTouchPoint.x - scaledHorizontal, max: displaySize.width - 1)
        scrollTouchPoint.y = clamp(scrollTouchPoint.y - scaledVertical, max: displaySize.height - 1)
        lastScrollInputAt = Date()

        let normalizedPoint = normalizedRemotePoint(for: scrollTouchPoint)
        Task { @MainActor [sessionClient] in
            await sessionClient.sendRemoteTouchMove(
                normalizedX: normalizedPoint.x,
                normalizedY: normalizedPoint.y
            )
        }
    }

    private func dispatchTrackpadPinchIfNeeded() {
        let pending: Double
        if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
            pending = pendingMagnification
        } else {
            pending = stateQueue.sync { pendingMagnification }
        }
        guard abs(pending) >= 0.018 else { return }

        let now = Date()
        guard now.timeIntervalSince(lastMagnifyAt) >= 0.16 else { return }
        lastMagnifyAt = now
        performHaptic(.pinchStep, minInterval: 0.08)

        let center: CGPoint
        let gain: Double
        if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
            center = normalizedRemotePoint(for: cursorPoint)
            gain = pinchGain
        } else {
            (center, gain) = stateQueue.sync {
                (normalizedRemotePoint(for: cursorPoint), pinchGain)
            }
        }
        let clampedMagnification: Double
        if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
            clampedMagnification = max(-1.0, min(1.0, pendingMagnification * 3.0 * gain))
            pendingMagnification = 0
        } else {
            clampedMagnification = stateQueue.sync { () -> Double in
                let value = max(-1.0, min(1.0, pendingMagnification * 3.0 * gain))
                pendingMagnification = 0
                return value
            }
        }

        if usesNativeHidInput() {
            let centerX = Int(max(0, min(32767, center.x * 32767)).rounded())
            let centerY = Int(max(0, min(32767, center.y * 32767)).rounded())
            var delta = Int((clampedMagnification * 1800).rounded())
            if abs(delta) < 260 {
                delta = clampedMagnification >= 0 ? 260 : -260
            }
            hidBridge.sendPinch(centerX: centerX, centerY: centerY, delta: delta, steps: 7)
            statusHandler?("트랙패드 pinch를 AOA HID 멀티터치로 전송")
            return
        }

        Task { @MainActor [sessionClient] in
            await sessionClient.sendRemotePinch(
                centerX: center.x,
                centerY: center.y,
                magnification: clampedMagnification
            )
        }
        statusHandler?("트랙패드 pinch를 Android 확대/축소 제스처로 전송")
    }

    private func performHaptic(_ intent: HapticIntent, minInterval: TimeInterval = 0.12) {
        let now = Date()
        let shouldPerform: Bool
        if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
            guard hapticsEnabled else { return }
            let previous = lastHapticAtByIntent[intent] ?? .distantPast
            guard now.timeIntervalSince(previous) >= minInterval else { return }
            lastHapticAtByIntent[intent] = now
            shouldPerform = true
        } else {
            shouldPerform = stateQueue.sync { () -> Bool in
                guard hapticsEnabled else { return false }
                let previous = lastHapticAtByIntent[intent] ?? .distantPast
                guard now.timeIntervalSince(previous) >= minInterval else { return false }
                lastHapticAtByIntent[intent] = now
                return true
            }
        }

        guard shouldPerform else { return }
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(intent.pattern, performanceTime: .now)
        }
    }

    private func parseVowel(in scalars: [Character], from index: Int) -> (index: Int, nextIndex: Int)? {
        guard index < scalars.count else { return nil }

        if index + 1 < scalars.count,
           let compoundIndex = Self.compoundVowelIndex[String([scalars[index], scalars[index + 1]])] {
            return (compoundIndex, index + 2)
        }

        guard let directIndex = Self.vowelIndex[scalars[index]] else { return nil }
        return (directIndex, index + 1)
    }

    private func isExitHotkey(keyCode: Int, flags: CGEventFlags) -> Bool {
        if keyCode == 53 {
            return true
        }

        if keyCode == 12 && flags.contains(.maskCommand) {
            return true
        }

        return keyCode == 123 &&
            flags.contains(.maskControl) &&
            flags.contains(.maskAlternate) &&
            flags.contains(.maskCommand)
    }

    private func setCursorHidden(_ hidden: Bool) {
        guard hidden != cursorHidden else { return }

        cursorHidden = hidden
        DispatchQueue.main.async {
            if hidden {
                NSCursor.hide()
            } else {
                NSCursor.unhide()
            }
        }
    }

    private func parkCursor() {
        let location: CGPoint
        if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
            location = parkedCursorLocation
        } else {
            location = stateQueue.sync { parkedCursorLocation }
        }
        DispatchQueue.main.async {
            CGWarpMouseCursorPosition(location)
        }
    }

    private func clamp(_ value: CGFloat, max: CGFloat) -> CGFloat {
        value.clamped(to: 0...max)
    }

    private func distanceBetween(_ start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return sqrt((dx * dx) + (dy * dy))
    }
}

private extension ControlModeInputController {
    static let leadingIndex: [Character: Int] = [
        "ㄱ": 0, "ㄲ": 1, "ㄴ": 2, "ㄷ": 3, "ㄸ": 4, "ㄹ": 5, "ㅁ": 6, "ㅂ": 7, "ㅃ": 8,
        "ㅅ": 9, "ㅆ": 10, "ㅇ": 11, "ㅈ": 12, "ㅉ": 13, "ㅊ": 14, "ㅋ": 15, "ㅌ": 16, "ㅍ": 17, "ㅎ": 18
    ]

    static let vowelIndex: [Character: Int] = [
        "ㅏ": 0, "ㅐ": 1, "ㅑ": 2, "ㅒ": 3, "ㅓ": 4, "ㅔ": 5, "ㅕ": 6, "ㅖ": 7,
        "ㅗ": 8, "ㅘ": 9, "ㅙ": 10, "ㅚ": 11, "ㅛ": 12, "ㅜ": 13, "ㅝ": 14, "ㅞ": 15,
        "ㅟ": 16, "ㅠ": 17, "ㅡ": 18, "ㅢ": 19, "ㅣ": 20
    ]

    static let trailingIndex: [Character: Int] = [
        "ㄱ": 1, "ㄲ": 2, "ㄳ": 3, "ㄴ": 4, "ㄵ": 5, "ㄶ": 6, "ㄷ": 7, "ㄹ": 8,
        "ㄺ": 9, "ㄻ": 10, "ㄼ": 11, "ㄽ": 12, "ㄾ": 13, "ㄿ": 14, "ㅀ": 15, "ㅁ": 16,
        "ㅂ": 17, "ㅄ": 18, "ㅅ": 19, "ㅆ": 20, "ㅇ": 21, "ㅈ": 22, "ㅊ": 23, "ㅋ": 24,
        "ㅌ": 25, "ㅍ": 26, "ㅎ": 27
    ]

    static let compoundVowelIndex: [String: Int] = [
        "ㅗㅏ": 9, "ㅗㅐ": 10, "ㅗㅣ": 11,
        "ㅜㅓ": 14, "ㅜㅔ": 15, "ㅜㅣ": 16,
        "ㅡㅣ": 19
    ]

    static let compoundTrailingIndex: [String: Int] = [
        "ㄱㅅ": 3, "ㄴㅈ": 5, "ㄴㅎ": 6, "ㄹㄱ": 9, "ㄹㅁ": 10, "ㄹㅂ": 11,
        "ㄹㅅ": 12, "ㄹㅌ": 13, "ㄹㅍ": 14, "ㄹㅎ": 15, "ㅂㅅ": 18
    ]

    static let standardizedHangulCharacter: [Character: Character] = [
        "ᄀ": "ㄱ", "ᄁ": "ㄲ", "ᄂ": "ㄴ", "ᄃ": "ㄷ", "ᄄ": "ㄸ", "ᄅ": "ㄹ", "ᄆ": "ㅁ", "ᄇ": "ㅂ", "ᄈ": "ㅃ",
        "ᄉ": "ㅅ", "ᄊ": "ㅆ", "ᄋ": "ㅇ", "ᄌ": "ㅈ", "ᄍ": "ㅉ", "ᄎ": "ㅊ", "ᄏ": "ㅋ", "ᄐ": "ㅌ", "ᄑ": "ㅍ", "ᄒ": "ㅎ",
        "ᅡ": "ㅏ", "ᅢ": "ㅐ", "ᅣ": "ㅑ", "ᅤ": "ㅒ", "ᅥ": "ㅓ", "ᅦ": "ㅔ", "ᅧ": "ㅕ", "ᅨ": "ㅖ", "ᅩ": "ㅗ", "ᅪ": "ㅘ",
        "ᅫ": "ㅙ", "ᅬ": "ㅚ", "ᅭ": "ㅛ", "ᅮ": "ㅜ", "ᅯ": "ㅝ", "ᅰ": "ㅞ", "ᅱ": "ㅟ", "ᅲ": "ㅠ", "ᅳ": "ㅡ", "ᅴ": "ㅢ",
        "ᅵ": "ㅣ",
        "ᆨ": "ㄱ", "ᆩ": "ㄲ", "ᆪ": "ㄳ", "ᆫ": "ㄴ", "ᆬ": "ㄵ", "ᆭ": "ㄶ", "ᆮ": "ㄷ", "ᆯ": "ㄹ", "ᆰ": "ㄺ", "ᆱ": "ㄻ",
        "ᆲ": "ㄼ", "ᆳ": "ㄽ", "ᆴ": "ㄾ", "ᆵ": "ㄿ", "ᆶ": "ㅀ", "ᆷ": "ㅁ", "ᆸ": "ㅂ", "ᆹ": "ㅄ", "ᆺ": "ㅅ", "ᆻ": "ㅆ",
        "ᆼ": "ㅇ", "ᆽ": "ㅈ", "ᆾ": "ㅊ", "ᆿ": "ㅋ", "ᇀ": "ㅌ", "ᇁ": "ㅍ", "ᇂ": "ㅎ"
    ]
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
