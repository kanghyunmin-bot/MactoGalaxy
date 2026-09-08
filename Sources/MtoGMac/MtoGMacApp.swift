import AppKit
import Darwin
import SwiftUI

/// Own the utility window explicitly: restoring closed SwiftUI scenes must not leave
/// a running process with no dashboard after launching from Finder or Spotlight.
@MainActor
final class MtoGAppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var loadingIdentity = false
    private var dashboard: NSWindow?
    private var settings: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "MtoG")
        appMenu.addItem(withTitle: "MtoG 설정…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "MtoG 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
        showDashboard()
        loadIdentity()
    }

    private func showDashboard() {
        if dashboard == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 820),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "MtoG"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 760, height: 620)
            window.contentView = NSHostingView(rootView: StartupView(message: "저장된 페어링 정보를 확인하고 있습니다. macOS 키체인 접근 창이 나타나면 MtoG를 허용하세요.", retry: nil))
            window.center()
            dashboard = window
        }
        dashboard?.deminiaturize(nil)
        dashboard?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadIdentity() {
        guard !loadingIdentity, model == nil else { return }
        loadingIdentity = true
        let deviceName = Host.current().localizedName ?? "Mac"
        Task { @MainActor [weak self] in
            let result = await Task.detached {
                Result { try DeviceIdentityStore().snapshot(deviceName: deviceName) }
            }.value
            guard let self else { return }
            loadingIdentity = false
            switch result {
            case .success(let identity):
                let readyModel = AppModel(identity: identity)
                model = readyModel
                dashboard?.contentView = NSHostingView(rootView: DashboardView(model: readyModel))
            case .failure(let error):
                dashboard?.contentView = NSHostingView(rootView: StartupView(
                    message: "기존 페어링 정보를 읽지 못했습니다. 키체인을 잠금 해제하고 다시 시도하세요. \(error.localizedDescription)",
                    retry: { [weak self] in self?.loadIdentity() }))
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return false
    }

    @objc private func showSettings() {
        guard let model else { showDashboard(); return }
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 340),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "MtoG 설정"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            settings = window
        }
        settings?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdownForTermination()
    }
}

@main
struct MtoGMacApp {
    @MainActor static func main() {
        signal(SIGPIPE, SIG_IGN)
        let application = NSApplication.shared
        let delegate = MtoGAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

private struct StartupView: View {
    let message: String
    let retry: (() -> Void)?
    var body: some View {
        VStack(spacing: 20) {
            Text("MtoG").font(.largeTitle.bold())
            if retry == nil { ProgressView() }
            Text(message).multilineTextAlignment(.center).frame(maxWidth: 480)
            if let retry { Button("다시 시도", action: retry) }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
