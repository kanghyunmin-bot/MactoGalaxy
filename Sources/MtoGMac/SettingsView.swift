import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section("확장 디스플레이") {
                Toggle("고화질 2560 × 1600 · 60Hz 목표", isOn: $model.highQualityDisplay)
                    .disabled(model.isExternalDisplayRunning)
                Text("끄면 1920 × 1200을 사용합니다. 실제 프레임률은 연결과 부하에 따라 달라집니다.")
                Text("태블릿 화면을 터치하면 Mac의 확장 화면을 조작합니다.")
            }
            Section("클립보드 공유") {
                Text("텍스트는 자동 동기화할 수 있습니다. 사진·파일은 클립보드 보내기로 공유합니다. 항목당 최대 24MB입니다.")
                Text("Galaxy에서 가져올 때는 잠금을 해제하세요. Samsung Keyboard는 그대로 사용할 수 있습니다.")
            }
        }.padding(20)
    }
}
