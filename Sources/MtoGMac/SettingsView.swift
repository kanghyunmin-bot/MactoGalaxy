import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var demoCode = "1408"

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("설정")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("테스트 페어링 코드")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        TextField("4자리 숫자", text: $demoCode)
                            .textFieldStyle(.roundedBorder)
                        Button("대시보드에 적용") {
                            model.applyDemoPairingCode(demoCode)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("대상 기기: \(model.targetName)", systemImage: "ipad")
                        Label("진입 위치: Mac 우측 상단 코너", systemImage: "arrow.up.right.and.arrow.down.left")
                        Label("복귀 위치: 갤럭시 좌측 하단 코너", systemImage: "arrow.down.left.and.arrow.up.right")
                        Label("코너 감지 범위: \(Int(model.edgeThreshold)) pt", systemImage: "move.3d")
                        Label("복귀 단축키: \(model.preferredExitHotkey)", systemImage: "keyboard")
                        Label("연결 방식: \(model.transportStatus.rawValue)", systemImage: "cable.connector")
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("제어 전환")
                            .font(.system(size: 14, weight: .bold, design: .rounded))

                        VStack(alignment: .leading, spacing: 8) {
                            Slider(value: $model.edgeThreshold, in: 4...32, step: 1)
                            Text(model.edgeInstructionText)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("macOS 입력 설정")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Spacer()
                            Button("macOS 설정 다시 읽기") {
                                model.refreshMacInputProfile()
                            }
                            .buttonStyle(.bordered)
                        }

                        profileRow("자연스러운 스크롤", value: boolLabel(model.macInputProfile.naturalScroll))
                        profileRow("관성 스크롤", value: boolLabel(model.macInputProfile.momentumScroll))
                        profileRow("탭하여 클릭", value: boolLabel(model.macInputProfile.tapToClick))
                        profileRow("보조 클릭", value: boolLabel(model.macInputProfile.secondaryClick))
                        profileRow("스와이프 제스처", value: boolLabel(model.macInputProfile.swipeGesture))
                        profileRow("핀치 제스처", value: boolLabel(model.macInputProfile.pinchGesture))
                        profileRow("세 손가락 드래그", value: boolLabel(model.macInputProfile.threeFingerDrag))
                        profileRow("트랙패드 속도", value: numberLabel(model.macInputProfile.trackpadScaling))
                        profileRow("마우스 속도", value: numberLabel(model.macInputProfile.mouseScaling))
                        profileRow(
                            "키 반복",
                            value: "지연 \(model.macInputProfile.initialKeyRepeat) · 반복 \(model.macInputProfile.keyRepeat)"
                        )
                        profileRow("햅틱", value: boolLabel(model.macInputProfile.hapticsEnabled))
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("입력 전달")
                            .font(.system(size: 14, weight: .bold, design: .rounded))

                        Toggle("macOS 시스템 설정 사용", isOn: $model.useSystemInputSettings)
                            .toggleStyle(.switch)

                        Text(model.useSystemInputSettings
                             ? "제어 모드가 시작될 때마다 현재 macOS의 트랙패드 속도, 스와이프, 핀치, 관성, 햅틱 설정을 따릅니다."
                             : "Android 제어 모드에서만 아래 수동 값을 사용합니다.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.muted)

                        profileRow(
                            "적용 포인터 감도",
                            value: numberLabel(Double(model.controlTuningProfile.pointerGain))
                        )
                        profileRow(
                            "적용 스크롤 감도",
                            value: numberLabel(model.controlTuningProfile.scrollGain)
                        )
                        profileRow(
                            "적용 핀치 감도",
                            value: numberLabel(model.controlTuningProfile.pinchGain)
                        )

                        if !model.useSystemInputSettings {
                            VStack(alignment: .leading, spacing: 10) {
                                sliderRow(
                                    title: "포인터 감도",
                                    value: $model.manualPointerGain,
                                    range: 1.0...4.0
                                )
                                sliderRow(
                                    title: "스크롤 감도",
                                    value: $model.manualScrollGain,
                                    range: 0.4...2.5
                                )
                                sliderRow(
                                    title: "핀치 감도",
                                    value: $model.manualPinchGain,
                                    range: 0.4...2.5
                                )

                                Toggle("스와이프 제스처 사용", isOn: $model.manualSwipeEnabled)
                                    .toggleStyle(.switch)
                                Toggle("핀치 제스처 사용", isOn: $model.manualPinchEnabled)
                                    .toggleStyle(.switch)
                                Toggle("Mac 로컬 햅틱 사용", isOn: $model.manualHapticsEnabled)
                                    .toggleStyle(.switch)
                            }
                        }
                    }
                    .padding(8)
                }

                Spacer()
            }
            .padding(24)
        }
    }

    private func profileRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.muted)
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                Spacer()
                Text(numberLabel(value.wrappedValue))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.muted)
            }
            Slider(value: value, in: range, step: 0.05)
        }
    }

    private func boolLabel(_ value: Bool) -> String {
        value ? "켬" : "끔"
    }

    private func numberLabel(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
