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
                Text("Settings")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Demo Pairing Code")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        TextField("4-digit code", text: $demoCode)
                            .textFieldStyle(.roundedBorder)
                        Button("Apply to Dashboard") {
                            model.applyDemoPairingCode(demoCode)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Target: \(model.targetName)", systemImage: "ipad")
                        Label("Enter Corner: Top Right Corner", systemImage: "arrow.up.right.and.arrow.down.left")
                        Label("Return Corner: Android Bottom Left", systemImage: "arrow.down.left.and.arrow.up.right")
                        Label("Corner Threshold: \(Int(model.edgeThreshold)) pt", systemImage: "move.3d")
                        Label("Exit Hotkey: \(model.preferredExitHotkey)", systemImage: "keyboard")
                        Label("Transport: \(model.transportStatus.rawValue)", systemImage: "cable.connector")
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Control Transition")
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
                            Text("macOS Input Profile")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Spacer()
                            Button("Refresh from macOS") {
                                model.refreshMacInputProfile()
                            }
                            .buttonStyle(.bordered)
                        }

                        profileRow("Natural Scroll", value: boolLabel(model.macInputProfile.naturalScroll))
                        profileRow("Momentum Scroll", value: boolLabel(model.macInputProfile.momentumScroll))
                        profileRow("Tap To Click", value: boolLabel(model.macInputProfile.tapToClick))
                        profileRow("Secondary Click", value: boolLabel(model.macInputProfile.secondaryClick))
                        profileRow("Swipe Gesture", value: boolLabel(model.macInputProfile.swipeGesture))
                        profileRow("Pinch Gesture", value: boolLabel(model.macInputProfile.pinchGesture))
                        profileRow("3-Finger Drag", value: boolLabel(model.macInputProfile.threeFingerDrag))
                        profileRow("Trackpad Speed", value: numberLabel(model.macInputProfile.trackpadScaling))
                        profileRow("Mouse Speed", value: numberLabel(model.macInputProfile.mouseScaling))
                        profileRow(
                            "Key Repeat",
                            value: "delay \(model.macInputProfile.initialKeyRepeat) · repeat \(model.macInputProfile.keyRepeat)"
                        )
                        profileRow("Haptics", value: boolLabel(model.macInputProfile.hapticsEnabled))
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Input Routing")
                            .font(.system(size: 14, weight: .bold, design: .rounded))

                        Toggle("Use macOS system settings", isOn: $model.useSystemInputSettings)
                            .toggleStyle(.switch)

                        Text(model.useSystemInputSettings
                             ? "Trackpad speed, swipe, pinch, momentum, and haptics follow current macOS settings whenever control mode starts."
                             : "Use manual override values for Android control mode only.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.muted)

                        profileRow(
                            "Effective Pointer Gain",
                            value: numberLabel(Double(model.controlTuningProfile.pointerGain))
                        )
                        profileRow(
                            "Effective Scroll Gain",
                            value: numberLabel(model.controlTuningProfile.scrollGain)
                        )
                        profileRow(
                            "Effective Pinch Gain",
                            value: numberLabel(model.controlTuningProfile.pinchGain)
                        )

                        if !model.useSystemInputSettings {
                            VStack(alignment: .leading, spacing: 10) {
                                sliderRow(
                                    title: "Pointer Sensitivity",
                                    value: $model.manualPointerGain,
                                    range: 1.0...4.0
                                )
                                sliderRow(
                                    title: "Scroll Sensitivity",
                                    value: $model.manualScrollGain,
                                    range: 0.4...2.5
                                )
                                sliderRow(
                                    title: "Pinch Sensitivity",
                                    value: $model.manualPinchGain,
                                    range: 0.4...2.5
                                )

                                Toggle("Enable swipe gestures", isOn: $model.manualSwipeEnabled)
                                    .toggleStyle(.switch)
                                Toggle("Enable pinch gestures", isOn: $model.manualPinchEnabled)
                                    .toggleStyle(.switch)
                                Toggle("Enable local haptics", isOn: $model.manualHapticsEnabled)
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
        value ? "On" : "Off"
    }

    private func numberLabel(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
