package com.mtog.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.material3.TextButton
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** Shell clipboard and mirror run outside the APK; never infer their state from connectivity. */
@Composable
internal fun ClipboardFeatureCard() {
    var expanded by rememberSaveable { mutableStateOf(false) }
    Card(modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xFFF8FBFA))) {
        Column(Modifier.padding(22.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("연결 후 할 수 있는 일", style = MaterialTheme.typography.titleLarge,
                color = Color(0xFF17202A), fontWeight = FontWeight.Bold)
            Text("Samsung Keyboard를 그대로 사용합니다. 기능은 Mac에서 켜고 끌 수 있습니다.",
                style = MaterialTheme.typography.bodyMedium, color = Color(0xFF5B6674))
            TextButton(onClick = { expanded = !expanded }) {
                Text(if (expanded) "사용 방법 접기" else "클립보드·화면 기능 사용 방법")
            }
            if (expanded) {
            FeatureDescription("01  자동 텍스트 · Mac ↔ Galaxy",
                "Mac에서 자동 동기화를 켜세요. 텍스트와 링크를 복사한 뒤 원하는 앱에 직접 붙여넣습니다.",
                "Samsung Keyboard 유지 · 실행 상태는 Mac에서 확인")
            HorizontalDivider()
            FeatureDescription("02  갤럭시 화면 보기 · Galaxy → Mac",
                "Mac의 미러링 시작을 누르면 갤럭시 앱을 Mac 창에서 보고 조작할 수 있습니다.",
                "Mac에서 시작·종료")
            HorizontalDivider()
            FeatureDescription("03  Mac 작업 공간 넓히기 · Mac → Galaxy",
                "Mac에서 실험적 확장 화면을 켜세요. 수신 화면이 열리면 실제 프레임 상태를 확인할 수 있습니다.",
                "화면 기록 권한은 Mac에서 허용")
            }
        }
    }
}

@Composable
private fun FeatureDescription(title: String, detail: String, note: String) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold, color = Color(0xFF1F4D5D))
        Text(detail, style = MaterialTheme.typography.bodyMedium, color = Color(0xFF17202A))
        Text(note, style = MaterialTheme.typography.labelMedium, color = Color(0xFF5B6674))
    }
}
