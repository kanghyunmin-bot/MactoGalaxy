import AppKit
import Darwin
import SwiftUI

final class MtoGAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("MtoG keeps active device transport sessions.")
        ProcessInfo.processInfo.disableSuddenTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct MtoGMacApp: App {
    @NSApplicationDelegateAdaptor(MtoGAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    init() {
        // A disconnected Android-side stream must not terminate the whole app.
        signal(SIGPIPE, SIG_IGN)
    }

    var body: some Scene {
        WindowGroup("MtoG") {
            DashboardView(model: model)
                .frame(minWidth: 1120, minHeight: 760)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.shutdownForTermination()
                }
        }
        .windowResizability(.contentSize)
        Settings {
            SettingsView(model: model)
                .frame(width: 700, height: 860)
        }
    }
}
