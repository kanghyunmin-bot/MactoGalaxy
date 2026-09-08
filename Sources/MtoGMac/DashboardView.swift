import AppKit
import SwiftUI
import MtoGCore

struct DashboardView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            DashboardBackground()

            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HeaderView(model: model)
                        ConnectionPanel(model: model)
                        ExternalDisplayPanel(model: model)
                        AutomaticClipboardPanel(model: model)
                        ClipboardPanel(model: model)
                        DetailsPanel(model: model)
                    }
                    .frame(maxWidth: 1320)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear { model.refreshDisplayPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshDisplayPermissions()
        }
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
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("MtoG").font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text("Mac과 Galaxy, 하나의 작업 공간")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.muted)
            }
            Spacer()
            StatusCapsule(title: model.adbStateText,
                detail: model.trustState.isTrusted ? "저장된 기기 · 연결 후 기능 사용" : "USB 연결 후 페어링하세요",
                systemImage: "cable.connector", tint: model.canUseUSBFeatures ? AppTheme.success : AppTheme.accent)
        }
        .padding(.vertical, 8)
    }
}

private struct AutomaticClipboardPanel: View {
    @ObservedObject var model: AppModel

    private var stateLabel: String {
        guard model.automaticClipboardEnabled else { return "꺼짐" }
        guard model.canUseUSBFeatures else { return "연결 대기" }
        switch model.clipboardAuthority {
        case .available: return "사용 중"
        case .negotiating: return "준비 중"
        case .failed: return "오류"
        case .unsupported: return "지원 확인 필요"
        case .permissionRequired, .blocked: return "확인 필요"
        case .stopped: return "대기 중"
        }
    }

    private var tint: Color {
        switch model.clipboardAuthority {
        case .available: return AppTheme.success
        case .failed: return AppTheme.danger
        case .permissionRequired, .unsupported, .blocked: return AppTheme.accentWarm
        default: return AppTheme.accent
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                SectionTitle("자동 텍스트 클립보드", subtitle: "Mac ↔ Galaxy · USB", systemImage: "doc.on.clipboard")
                Spacer()
                Text(stateLabel)
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(tint.opacity(0.12), in: Capsule())
                    .foregroundStyle(tint)
            }
            Text("복사한 텍스트와 링크를 두 기기에서 이어 쓰세요.")
                .font(.system(size: 24, weight: .bold)).foregroundStyle(AppTheme.ink)
            Label(model.automaticClipboardStatus, systemImage: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(model.automaticClipboardEnabled ? "자동 동기화 중지" : "자동 동기화 켜기") {
                    model.toggleAutomaticClipboard()
                }
                .buttonStyle(PrimaryActionButtonStyle(tint: tint))
                .disabled(!model.automaticClipboardEnabled && !model.canUseUSBFeatures)
                if model.canRetryClipboard {
                    Button("다시 시도") { model.retryAutomaticClipboard() }
                        .buttonStyle(SecondaryActionButtonStyle())
                }
                if !model.canUseUSBFeatures {
                    Text("신뢰된 USB 연결이 필요합니다")
                        .font(.system(size: 12)).foregroundStyle(AppTheme.muted)
                }
            }
            Divider()
            HStack(spacing: 22) {
                Label("Samsung Keyboard 유지", systemImage: "keyboard")
                Label("USB로 공유", systemImage: "cable.connector")
                Label("붙여넣기는 직접", systemImage: "hand.tap")
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.muted)
            DisclosureGroup("동기화가 멈췄을 때") {
                Text("갤럭시 잠금을 해제하고 텍스트를 복사해 보세요. 연결이 끊겼다면 USB를 다시 연결하세요. 오류가 계속되면 다시 시도를 누르세요. 이미지와 파일은 아래 수동 전송을 사용합니다.")
                    .font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                    .padding(.top, 8).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 13, weight: .medium))
        }
        .surfaceCard(padding: 24)
    }
}

private struct ExternalDisplayPanel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle("Mac 작업 공간 넓히기", subtitle: "Mac 확장 디스플레이 · 터치 입력", systemImage: "display.2")
            Label("Mac  →  Galaxy 보조 화면", systemImage: "rectangle.expand.vertical")
                .font(.system(size: 20, weight: .bold)).foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 90)
                .background(AppTheme.success.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            Text(model.externalDisplayStatusText)
                .font(.system(size: 14, weight: .medium)).foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Mac의 창을 갤럭시로 옮겨 별도 작업 공간으로 사용합니다. 실제 화면 수신 상태는 갤럭시에서 확인하세요.")
                .font(.system(size: 13)).foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("고화질 2560 × 1600 · 60Hz 목표", isOn: $model.highQualityDisplay)
                .disabled(model.isExternalDisplayRunning)
                .font(.system(size: 13))
            Button(model.isExternalDisplayRunning ? "확장 화면 종료" : "확장 화면 시작") {
                if model.isExternalDisplayRunning { model.stopExternalDisplayMode() }
                else { model.startExternalDisplayMode() }
            }
            .buttonStyle(PrimaryActionButtonStyle(tint: model.isExternalDisplayRunning ? AppTheme.accentWarm : AppTheme.success))
            .disabled(!model.isExternalDisplayRunning && !model.canUseUSBFeatures)
            HStack {
                Label(model.screenRecordingAllowed ? "화면 기록 허용됨" : "화면 기록 허용 필요",
                      systemImage: model.screenRecordingAllowed ? "checkmark.circle" : "exclamationmark.circle")
                Label(model.touchInputAllowed ? "터치 입력 허용됨" : "터치 입력 허용 필요",
                      systemImage: model.touchInputAllowed ? "checkmark.circle" : "exclamationmark.circle")
            }.font(.system(size: 13))
            HStack {
                Button("화면 기록 설정") { model.openScreenRecordingSettings() }
                Button("터치 권한 설정") { model.openTouchPermissionSettings() }
            }
            .buttonStyle(SecondaryActionButtonStyle())
            Text("화면 기록: 화면 전송에 필요 · 손쉬운 사용: 터치 조작 시 필요")
                .font(.system(size: 12)).foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(padding: 24)
    }
}

private struct ConnectionPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("1. 기기 연결", subtitle: "USB 연결 → 갤럭시 코드 입력 → 페어링 저장", systemImage: "lock.shield")

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    InfoRow("상태", value: model.adbStateText)
                    InfoRow("신뢰", value: model.trustState.lastPairedDescription)
                    InfoRow("최근 연결", value: model.trustState.lastSeenDescription)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    Text("페어링 코드")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    TextField(
                        "갤럭시에 표시된 4자리 코드",
                        text: Binding(
                            get: { model.enteredPairingCode },
                            set: { model.updatePairingCode($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppTheme.panelStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            DisclosureGroup("Wi-Fi로 수동 전송하기") {
              VStack(alignment: .leading, spacing: 10) {
                Text("무선 연결")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text("개인 Wi-Fi, 개인 핫스팟, 신뢰할 수 있는 LAN을 사용하세요. 학교/공용 네트워크는 기기 검색이나 직접 연결을 막을 수 있습니다.")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.wirelessDiscoveryStatus)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accentWarm)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    TextField("갤럭시 IP 직접 입력", text: $model.wirelessHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))

                    Button("IP로 연결") {
                        Task { await model.connectWirelessSession() }
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }

                HStack(spacing: 8) {
                    Button("Wi-Fi 검색") {
                        model.startWirelessDiscovery()
                    }
                    .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.success))

                    Button("찾은 기기 연결") {
                        Task { await model.connectFirstDiscoveredWirelessPeer() }
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .disabled(model.discoveredWirelessPeers.isEmpty)

                    Button("검색 중지") {
                        model.stopWirelessDiscovery()
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }

                if !model.discoveredWirelessPeers.isEmpty {
                    VStack(spacing: 7) {
                        ForEach(model.discoveredWirelessPeers) { peer in
                            Button {
                                Task { await model.connectDiscoveredWirelessPeer(peer) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "wifi")
                                        .foregroundStyle(AppTheme.success)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(peer.name)
                                            .font(.system(size: 12, weight: .black, design: .rounded))
                                            .foregroundStyle(AppTheme.ink)
                                        Text(peer.detail)
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                            .foregroundStyle(AppTheme.muted)
                                    }
                                    Spacer()
                                    Text("연결")
                                        .font(.system(size: 11, weight: .black, design: .rounded))
                                        .foregroundStyle(AppTheme.accent)
                                }
                                .padding(10)
                                .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
            .background(AppTheme.panelStrong, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 10) {
                Button("USB 연결") {
                    Task { await model.connectADBSession() }
                }
                .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.accent))

                Button("페어링 저장") {
                    model.startPairing()
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(model.sessionClient.state != .connected || model.enteredPairingCode.count != 4)

                Button("연결 해제") {
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
                SectionTitle("사진·파일 공유", subtitle: "Mac ↔ Galaxy · 최대 24MB / 항목", systemImage: "clipboard")
                Spacer()
                Button(model.isClipboardHistoryVisible ? "히스토리 숨기기" : "히스토리 보기") {
                    model.toggleClipboardHistory()
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }

            Text(model.clipboardSyncStatus)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Mac 클립보드 보내기") {
                    model.pushCurrentClipboardToAndroid()
                }
                .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.accent))

                Button("사진·파일 선택") { model.chooseFileToShare() }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .disabled(!model.canUseUSBFeatures)

                Button("갤럭시 클립보드 가져오기") {
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
                InfoRow("갤럭시", value: model.targetName)
                InfoRow("연결 방식", value: model.sessionClient.activeTransportDescription)
                InfoRow("상태 확인", value: model.sessionClient.healthText)
                if let last = model.sessionClient.lastReceivedMessage {
                    InfoRow("최근 수신", value: "\(last.type.rawValue) · \(last.deviceName)")
                }
                if let error = model.sessionClient.lastErrorMessage {
                    InfoRow("최근 오류", value: error)
                }
            }
            .padding(.top, 12)
        } label: {
            SectionTitle("자세히", subtitle: "연결 진단 정보", systemImage: "stethoscope")
        }
        .surfaceCard(padding: 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
            Text("아직 클립보드 기록이 없습니다")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Text("텍스트, 이미지, 파일을 한 번 동기화하면 여기에 표시됩니다.")
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
                Button("다시 복사", action: onRecopy)
                    .buttonStyle(CompactActionButtonStyle())
                    .disabled(!item.canReCopy)
                Button("저장", action: onDownload)
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
