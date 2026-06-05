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
                    ConnectionPanel(model: model)

                    HStack(alignment: .top, spacing: 18) {
                        MirrorPanel(model: model)
                        ClipboardPanel(model: model)
                    }

                    HStack(alignment: .top, spacing: 18) {
                        ExternalDisplayPanel(model: model)
                        DetailsPanel(model: model)
                    }
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
                Text("갤럭시 탭을 Wi-Fi 또는 USB로 연결하고, 미러링과 클립보드를 함께 사용합니다.")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                StatusCapsule(
                    title: model.connectionStatus.rawValue,
                    detail: model.sessionClient.activeTransportDescription,
                    systemImage: "point.3.connected.trianglepath.dotted",
                    tint: model.connectionStatus == .trusted || model.connectionStatus == .active ? AppTheme.success : AppTheme.accent
                )
                StatusCapsule(
                    title: model.isMirrorRunning ? "미러링 실행 중" : "미러링 대기 중",
                    detail: model.mirrorStatusText,
                    systemImage: "rectangle.connected.to.line.below",
                    tint: model.isMirrorRunning ? AppTheme.success : AppTheme.accentWarm
                )
            }
        }
        .surfaceCard(padding: 24)
    }
}

private struct MirrorPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle("갤럭시 미러링", subtitle: "창 안에서만 조작", systemImage: "display")

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.isMirrorRunning ? "갤럭시 화면이 열려 있습니다" : "갤럭시 화면을 Mac에 띄우기")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text(model.mirrorStatusText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("마우스가 미러링 창 안에 있을 때만 갤럭시를 조작합니다. 창 밖으로 나오면 바로 Mac 조작으로 돌아옵니다.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.muted)
                }

                Spacer()

                VStack(spacing: 10) {
                    Button(model.isMirrorRunning ? "미러링 종료" : "USB 미러링 시작") {
                        if model.isMirrorRunning {
                            model.stopMirrorMode()
                        } else {
                            model.startMirrorMode()
                        }
                    }
                    .buttonStyle(PrimaryActionButtonStyle(tint: model.isMirrorRunning ? AppTheme.accentWarm : AppTheme.accent))

                    Button("USB 세션 다시 연결") {
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
            SectionTitle("외장 디스플레이", subtitle: "실험적 보조 화면", systemImage: "rectangle.inset.filled.and.person.filled")

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("갤럭시 탭을 Mac의 별도 화면처럼 써야 할 때만 사용하세요.")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.ink)

                    Text("실험 기능입니다. macOS 가상 디스플레이와 ADB 스트리밍을 사용하므로 화면 오류, 잔여 디스플레이 상태, 성능 저하가 생길 수 있습니다. 안정적인 사용은 미러링을 권장합니다.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(model.externalDisplayStatusText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("실험적 외장 디스플레이 허용", isOn: $model.allowExperimentalExternalDisplay)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                }

                Spacer()

                VStack(spacing: 10) {
                    StatusCapsule(
                        title: model.isExternalDisplayRunning ? "디스플레이 실행 중" : "디스플레이 대기 중",
                        detail: model.allowExperimentalExternalDisplay ? "실험 기능 허용됨" : "먼저 허용 스위치를 켜세요",
                        systemImage: "display.2",
                        tint: model.isExternalDisplayRunning ? AppTheme.success : AppTheme.accentWarm
                    )
                    .frame(width: 260)

                    Button(model.isExternalDisplayRunning ? "외장 디스플레이 종료" : "외장 디스플레이 시작") {
                        if model.isExternalDisplayRunning {
                            model.stopExternalDisplayMode()
                        } else {
                            model.startExternalDisplayMode()
                        }
                    }
                    .buttonStyle(PrimaryActionButtonStyle(tint: model.isExternalDisplayRunning ? AppTheme.accentWarm : AppTheme.success))
                    .disabled(!model.allowExperimentalExternalDisplay)

                    Button("강제 종료") {
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
            SectionTitle("연결 허브", subtitle: "페어링, USB, 개인 Wi-Fi", systemImage: "lock.shield")

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

            HStack(spacing: 10) {
                Button("USB 연결") {
                    Task { await model.connectADBSession() }
                }
                .buttonStyle(PrimaryActionButtonStyle(tint: AppTheme.accent))

                Button("페어링 저장") {
                    model.startPairing()
                }
                .buttonStyle(SecondaryActionButtonStyle())

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
                SectionTitle("클립보드", subtitle: "버튼으로 직접 동기화", systemImage: "clipboard")
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
                InfoRow("조작", value: model.controlStatusText)
                InfoRow("전환 위치", value: model.edgeInstructionText)
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
