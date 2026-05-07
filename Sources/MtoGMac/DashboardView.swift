import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            DashboardBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HeaderView(model: model)
                    MirrorPanel(model: model)
                    ExternalDisplayPanel(model: model)

                    HStack(alignment: .top, spacing: 18) {
                        ConnectionPanel(model: model)
                        ClipboardPanel(model: model)
                    }

                    DetailsPanel(model: model)
                }
                .padding(28)
            }
        }
        .preferredColorScheme(.light)
    }
}

private struct DashboardBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.94, green: 0.93, blue: 0.88), Color(red: 0.79, green: 0.87, blue: 0.89)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.08, green: 0.24, blue: 0.30).opacity(0.26), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 560
            )
            RadialGradient(
                colors: [Color(red: 0.76, green: 0.36, blue: 0.24).opacity(0.18), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}

private struct HeaderView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("MtoG")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text("High-quality USB mirror and manual clipboard for Galaxy Tab.")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            StatusCapsule(
                title: model.isMirrorRunning ? "Mirror Running" : "Mirror Idle",
                detail: model.mirrorStatusText,
                systemImage: "rectangle.connected.to.line.below",
                tint: model.isMirrorRunning ? AppTheme.success : AppTheme.accent
            )
        }
        .surfaceCard(padding: 24)
    }
}

private struct MirrorPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(
                "Galaxy Mirror",
                subtitle: "USB scrcpy window-local control",
                systemImage: "display"
            )

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.isMirrorRunning ? "Mirror window is active" : "Start the Galaxy mirror window")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text(model.mirrorStatusText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Control stays inside the scrcpy window. Move the Mac pointer outside the mirror window to return to macOS immediately.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                VStack(spacing: 10) {
                    Button(model.isMirrorRunning ? "Stop Mirror" : "Start USB Mirror") {
                        if model.isMirrorRunning {
                            model.stopMirrorMode()
                        } else {
                            model.startMirrorMode()
                        }
                    }
                    .buttonStyle(PrimaryActionButtonStyle(tint: model.isMirrorRunning ? AppTheme.accentWarm : AppTheme.accent))

                    Button("Reconnect ADB Session") {
                        Task { await model.connectADBSession() }
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }
                .frame(width: 190)
            }
        }
        .surfaceCard(padding: 24)
    }
}

private struct ExternalDisplayPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(
                "External Display",
                subtitle: "Experimental virtual second-screen mode",
                systemImage: "rectangle.inset.filled.and.person.filled"
            )

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Use this only when you need the Galaxy Tab as a separate Mac display.")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.ink)

                    Text("Experimental: this uses a private macOS virtual display API and JPEG-over-ADB streaming. It can glitch, leave display state behind, or perform poorly. Mirror is the stable control mode.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(model.externalDisplayStatusText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Enable experimental external display", isOn: $model.allowExperimentalExternalDisplay)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                }

                Spacer()

                VStack(spacing: 10) {
                    StatusCapsule(
                        title: model.isExternalDisplayRunning ? "Display Running" : "Display Idle",
                        detail: model.allowExperimentalExternalDisplay ? "Experimental enabled" : "Enable toggle first",
                        systemImage: "display.2",
                        tint: model.isExternalDisplayRunning ? AppTheme.success : AppTheme.accentWarm
                    )
                    .frame(width: 260)

                    Button(model.isExternalDisplayRunning ? "Stop External Display" : "Start External Display") {
                        if model.isExternalDisplayRunning {
                            model.stopExternalDisplayMode()
                        } else {
                            model.startExternalDisplayMode()
                        }
                    }
                    .buttonStyle(PrimaryActionButtonStyle(tint: model.isExternalDisplayRunning ? AppTheme.accentWarm : AppTheme.success))
                    .disabled(!model.allowExperimentalExternalDisplay)

                    Button("Force Stop") {
                        model.stopExternalDisplayMode()
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }
                .frame(width: 270)
            }
        }
        .surfaceCard(padding: 24)
    }
}

private struct ConnectionPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Connection", subtitle: "Trust and ADB session", systemImage: "lock.shield")

            VStack(spacing: 10) {
                InfoRow("ADB", value: model.adbStateText)
                InfoRow("Trust", value: model.trustState.lastPairedDescription)
                InfoRow("Last seen", value: model.trustState.lastSeenDescription)
            }

            HStack(spacing: 8) {
                ForEach(Array(model.pairingCode.enumerated()), id: \.offset) { _, digit in
                    Text(digit.isEmpty ? "-" : digit)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 54, height: 58)
                        .background(AppTheme.panelStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            Text(model.pairingStatusText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Connect USB") {
                    Task { await model.connectADBSession() }
                }
                .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.accent))

                Button("Pair & Trust") {
                    model.startPairing()
                }
                .buttonStyle(SecondaryActionButtonStyle())

                Button("Disconnect") {
                    model.sessionClient.disconnect()
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .surfaceCard(padding: 22)
    }
}

private struct ClipboardPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle("Clipboard", subtitle: "Manual sync only", systemImage: "clipboard")
                Spacer()
                Button(model.isClipboardHistoryVisible ? "Hide History" : "Show History") {
                    model.toggleClipboardHistory()
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }

            Text(model.clipboardSyncStatus)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Push Mac Clipboard") {
                    model.pushCurrentClipboardToAndroid()
                }
                .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.accent))

                Button("Pull Galaxy Clipboard") {
                    model.requestAndroidClipboardPull()
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }

            if model.isClipboardHistoryVisible {
                VStack(spacing: 10) {
                    if model.clipboardHistory.isEmpty {
                        EmptyHistoryView()
                    } else {
                        ForEach(model.clipboardHistory) { item in
                            HistoryRow(
                                item: item,
                                onRecopy: { model.recopyClipboardHistoryItem(item) },
                                onDownload: { model.downloadClipboardHistoryItem(item) }
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .surfaceCard(padding: 22)
    }
}

private struct DetailsPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 10) {
                InfoRow("Mac", value: model.deviceName)
                InfoRow("Target", value: model.targetName)
                InfoRow("Transport", value: model.sessionClient.activeTransportDescription)
                InfoRow("Health", value: model.sessionClient.healthText)
                InfoRow("Control", value: model.controlStatusText)
                InfoRow("Corner mode", value: model.edgeInstructionText)
                if let last = model.sessionClient.lastReceivedMessage {
                    InfoRow("Last inbound", value: "\(last.type.rawValue) from \(last.deviceName)")
                }
                if let error = model.sessionClient.lastErrorMessage {
                    InfoRow("Last error", value: error)
                }
            }
            .padding(.top, 12)
        } label: {
            SectionTitle("Details", subtitle: "Diagnostics, not primary controls", systemImage: "stethoscope")
        }
        .surfaceCard(padding: 20)
    }
}

private struct SectionTitle: View {
    let title: String
    let subtitle: String
    let systemImage: String

    init(_ title: String, subtitle: String, systemImage: String) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.muted)
            }
        }
    }
}

private struct StatusCapsule: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.white)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 38, height: 38)
                .background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
            }
        }
        .frame(width: 330, alignment: .leading)
        .padding(12)
        .background(AppTheme.panelStrong, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.accentWarm)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppTheme.panelStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(AppTheme.accent)
            Text("No clipboard history yet")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Text("Sync a text, image, or file item first.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(AppTheme.panelStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct HistoryRow: View {
    let item: ClipboardHistoryItem
    let onRecopy: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HistoryThumbnail(item: item)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                Text("\(item.detail) · \(item.sizeLabel)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Button("Re-copy", action: onRecopy)
                    .buttonStyle(CompactActionButtonStyle())
                    .disabled(!item.canReCopy)
                Button("Download", action: onDownload)
                    .buttonStyle(CompactActionButtonStyle())
                    .disabled(!item.canDownload)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct HistoryThumbnail: View {
    let item: ClipboardHistoryItem

    var body: some View {
        Group {
            if item.kind == .image,
               let path = item.cachedFilePath,
               let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .frame(width: 42, height: 42)
        .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 16)
            .frame(minWidth: 128, minHeight: 38)
            .background(tint.opacity(isEnabled ? (configuration.isPressed ? 0.84 : 1.0) : 0.28), in: Capsule())
            .shadow(color: tint.opacity(isEnabled ? 0.18 : 0), radius: 10, x: 0, y: 6)
            .opacity(isEnabled ? 1 : 0.55)
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(isEnabled ? AppTheme.ink : AppTheme.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 14)
            .frame(minWidth: 104, minHeight: 36)
            .background(
                (configuration.isPressed ? AppTheme.accentSoft : AppTheme.panelStrong)
                    .opacity(isEnabled ? 1 : 0.58),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(AppTheme.panelStroke, lineWidth: 1)
            )
    }
}

private struct CompactActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(isEnabled ? AppTheme.ink : AppTheme.muted)
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(
                (configuration.isPressed ? AppTheme.accentSoft : Color.white.opacity(0.82))
                    .opacity(isEnabled ? 1 : 0.48),
                in: Capsule()
            )
            .overlay(Capsule().stroke(AppTheme.panelStroke, lineWidth: 1))
    }
}

private extension View {
    func surfaceCard(padding: CGFloat) -> some View {
        self
            .padding(padding)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.panelStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 20, x: 0, y: 12)
    }
}
