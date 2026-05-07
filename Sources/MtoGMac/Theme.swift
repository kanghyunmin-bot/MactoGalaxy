import SwiftUI

enum AppTheme {
    static let backgroundTop = Color(red: 0.96, green: 0.94, blue: 0.89)
    static let backgroundBottom = Color(red: 0.84, green: 0.90, blue: 0.92)
    static let glowBlue = Color(red: 0.19, green: 0.39, blue: 0.48).opacity(0.22)
    static let glowWarm = Color(red: 0.82, green: 0.46, blue: 0.34).opacity(0.18)
    static let panel = Color.white.opacity(0.80)
    static let panelStrong = Color.white.opacity(0.92)
    static let panelStroke = Color.black.opacity(0.08)
    static let ink = Color(red: 0.10, green: 0.13, blue: 0.17)
    static let muted = Color(red: 0.34, green: 0.39, blue: 0.45)
    static let accent = Color(red: 0.13, green: 0.31, blue: 0.40)
    static let accentSoft = Color(red: 0.81, green: 0.88, blue: 0.89)
    static let accentWarm = Color(red: 0.68, green: 0.35, blue: 0.27)
    static let success = Color(red: 0.16, green: 0.48, blue: 0.32)
    static let warning = Color(red: 0.74, green: 0.50, blue: 0.16)
    static let danger = Color(red: 0.72, green: 0.22, blue: 0.18)
}

struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(AppTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(AppTheme.panelStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 22, x: 0, y: 12)
    }
}

extension View {
    func glassPanel() -> some View {
        modifier(GlassPanel())
    }
}
