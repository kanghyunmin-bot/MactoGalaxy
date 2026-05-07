import AppKit
import Foundation

enum ControlCorner: String, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft:
            return "Top Left Corner"
        case .topRight:
            return "Top Right Corner"
        case .bottomLeft:
            return "Bottom Left Corner"
        case .bottomRight:
            return "Bottom Right Corner"
        }
    }

    var shortLabel: String {
        switch self {
        case .topLeft:
            return "top-left"
        case .topRight:
            return "top-right"
        case .bottomLeft:
            return "bottom-left"
        case .bottomRight:
            return "bottom-right"
        }
    }
}

@MainActor
final class PointerEdgeMonitor {
    var configuredCorner: ControlCorner = .topRight
    var threshold: CGFloat = 12
    var activationHandler: ((ControlCorner, CGPoint) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isInsideConfiguredBand = false

    func start() {
        stop()

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.evaluateCurrentPointerPosition()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.evaluateCurrentPointerPosition()
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        isInsideConfiguredBand = false
    }

    private func evaluateCurrentPointerPosition() {
        let location = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else {
            isInsideConfiguredBand = false
            return
        }

        let isInsideBand = cornerContains(location: location, screenFrame: screen.frame)
        defer { isInsideConfiguredBand = isInsideBand }

        guard isInsideBand, !isInsideConfiguredBand else { return }
        activationHandler?(configuredCorner, location)
    }

    private func cornerContains(location: CGPoint, screenFrame: CGRect) -> Bool {
        switch configuredCorner {
        case .topLeft:
            return location.x <= screenFrame.minX + threshold &&
                location.y >= screenFrame.maxY - threshold
        case .topRight:
            return location.x >= screenFrame.maxX - threshold &&
                location.y >= screenFrame.maxY - threshold
        case .bottomLeft:
            return location.x <= screenFrame.minX + threshold &&
                location.y <= screenFrame.minY + threshold
        case .bottomRight:
            return location.x >= screenFrame.maxX - threshold &&
                location.y <= screenFrame.minY + threshold
        }
    }
}
