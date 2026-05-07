import AppKit

@MainActor
final class GestureCaptureOverlay {
    private final class GestureWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private final class GestureView: NSView {
        var magnifyHandler: ((NSEvent) -> Void)?
        var swipeHandler: ((NSEvent) -> Void)?
        var smartMagnifyHandler: ((NSEvent) -> Void)?
        var magnificationDeltaHandler: ((CGFloat) -> Void)?
        private var lastTouchPairDistance: CGFloat?

        override var acceptsFirstResponder: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            acceptsTouchEvents = true
            allowedTouchTypes = [.indirect]
            let magnificationRecognizer = NSMagnificationGestureRecognizer(
                target: self,
                action: #selector(handleMagnificationRecognizer(_:))
            )
            addGestureRecognizer(magnificationRecognizer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func magnify(with event: NSEvent) {
            magnifyHandler?(event)
        }

        override func swipe(with event: NSEvent) {
            swipeHandler?(event)
        }

        override func smartMagnify(with event: NSEvent) {
            smartMagnifyHandler?(event)
        }

        override func touchesBegan(with event: NSEvent) {
            super.touchesBegan(with: event)
            handleTouchEvent(event)
        }

        override func touchesMoved(with event: NSEvent) {
            super.touchesMoved(with: event)
            handleTouchEvent(event)
        }

        override func touchesEnded(with event: NSEvent) {
            super.touchesEnded(with: event)
            handleTouchEvent(event)
        }

        override func touchesCancelled(with event: NSEvent) {
            super.touchesCancelled(with: event)
            lastTouchPairDistance = nil
        }

        @objc
        private func handleMagnificationRecognizer(_ recognizer: NSMagnificationGestureRecognizer) {
            guard recognizer.state == .changed || recognizer.state == .ended else { return }
            let delta = recognizer.magnification
            guard abs(delta) > 0.001 else { return }
            magnificationDeltaHandler?(delta)
            recognizer.magnification = 0
        }

        private func handleTouchEvent(_ event: NSEvent) {
            let touching = Array(event.touches(matching: .touching, in: self))
            guard touching.count >= 2 else {
                lastTouchPairDistance = nil
                return
            }

            let pair = touching.prefix(2)
            let p1 = pair[pair.startIndex].normalizedPosition
            let p2 = pair[pair.index(after: pair.startIndex)].normalizedPosition
            let dx = CGFloat(p1.x - p2.x)
            let dy = CGFloat(p1.y - p2.y)
            let distance = sqrt((dx * dx) + (dy * dy))

            if let lastTouchPairDistance {
                let delta = distance - lastTouchPairDistance
                if abs(delta) >= 0.0025 {
                    magnificationDeltaHandler?(delta * 5.0)
                }
            }

            lastTouchPairDistance = distance
        }
    }

    private let window: GestureWindow
    private let view: GestureView

    init(frame: CGRect) {
        let view = GestureView(frame: CGRect(origin: .zero, size: frame.size))
        self.view = view
        self.window = GestureWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.contentView = view
    }

    func updateHandlers(
        onMagnify: @escaping (NSEvent) -> Void,
        onMagnificationDelta: @escaping (CGFloat) -> Void,
        onSwipe: @escaping (NSEvent) -> Void,
        onSmartMagnify: @escaping (NSEvent) -> Void
    ) {
        view.magnifyHandler = onMagnify
        view.magnificationDeltaHandler = onMagnificationDelta
        view.swipeHandler = onSwipe
        view.smartMagnifyHandler = onSmartMagnify
    }

    func present() {
        NSApp.activate()
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    func dismiss() {
        window.orderOut(nil)
        window.close()
    }
}
