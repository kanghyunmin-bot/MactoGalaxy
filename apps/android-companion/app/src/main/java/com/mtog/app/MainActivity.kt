package com.mtog.app

import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.mtog.app.clipboard.ClipboardHistoryRecord
import com.mtog.app.clipboard.ClipboardHistoryStore
import com.mtog.app.pairing.PairingStore
import com.mtog.app.pairing.PairingUiState
import com.mtog.app.service.SessionForegroundService
import com.mtog.app.session.SessionRuntime
import com.mtog.app.session.SessionRuntimeState
import com.mtog.app.ui.theme.MtoGTheme

private val Ink = Color(0xFF17202A)
private val Muted = Color(0xFF5B6674)
private val Panel = Color.White.copy(alpha = 0.84f)
private val PanelStrong = Color.White.copy(alpha = 0.94f)
private val Accent = Color(0xFF1F4D5D)
private val Warm = Color(0xFFA85E46)
private val Success = Color(0xFF277A5B)
private val SoftBlue = Color(0xFFDDE9EA)

class MainActivity : ComponentActivity() {
    companion object {
        const val actionSyncClipboard = "com.mtog.app.action.SYNC_CLIPBOARD"
    }

    private val clipboardSyncHandler = Handler(Looper.getMainLooper())
    private var pendingForegroundClipboardSync = false
    private var foregroundClipboardSyncAttempts = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MtoGTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    HomeScreen()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (intent?.action == actionSyncClipboard) {
            requestForegroundClipboardSync()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == actionSyncClipboard) {
            requestForegroundClipboardSync()
        }
    }

    override fun onPause() {
        clipboardSyncHandler.removeCallbacksAndMessages(null)
        pendingForegroundClipboardSync = false
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && pendingForegroundClipboardSync) {
            scheduleForegroundClipboardSyncAttempt(delayMs = 40L)
        }
    }

    private fun requestForegroundClipboardSync() {
        pendingForegroundClipboardSync = true
        foregroundClipboardSyncAttempts = 0
        ContextCompat.startForegroundService(
            this,
            Intent(this, SessionForegroundService::class.java)
                .setAction(SessionForegroundService.actionSyncClipboard)
        )
        clipboardSyncHandler.removeCallbacksAndMessages(null)
        scheduleForegroundClipboardSyncAttempt(delayMs = 180L)
    }

    private fun scheduleForegroundClipboardSyncAttempt(delayMs: Long) {
        clipboardSyncHandler.postDelayed({
            if (!pendingForegroundClipboardSync) {
                return@postDelayed
            }
            foregroundClipboardSyncAttempts += 1
            val synced = SessionForegroundService.syncClipboardNow()
            if (!synced && foregroundClipboardSyncAttempts < 5) {
                scheduleForegroundClipboardSyncAttempt(delayMs = 180L)
            } else {
                pendingForegroundClipboardSync = false
            }
        }, delayMs)
    }

}

@Composable
private fun HomeScreen() {
    val context = LocalContext.current
    val sessionState by SessionRuntime.state.collectAsState()
    val history by ClipboardHistoryStore.history.collectAsState()
    val pairingState by PairingStore.state.collectAsState()
    var showClipboardHistory by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        ClipboardHistoryStore.initialize(context)
        PairingStore.initialize(context)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.linearGradient(
                    colors = listOf(
                        Color(0xFFF6EFE5),
                        Color(0xFFE6EEF0),
                        Color(0xFFD8E4E5)
                    )
                )
            )
            .padding(18.dp)
    ) {
        BoxWithConstraints {
            val wide = maxWidth >= 820.dp
            LazyColumn(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                item {
                    HeaderCard()
                }
                item {
                    StatusOverviewCard(sessionState = sessionState)
                }
                item { ClipboardFeatureCard() }
                if (wide) {
                    item {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(14.dp)
                        ) {
                            PairingCard(
                                state = pairingState,
                                onPairingCodeChange = { PairingStore.updateEnteredCode(it) },
                                onGeneratePairingCode = { PairingStore.regeneratePairingCode() },
                                modifier = Modifier.weight(1f)
                            )
                            TransportCard(
                                sessionState = sessionState,
                                onRestartServer = {
                                    ContextCompat.startForegroundService(
                                        context,
                                        Intent(context, SessionForegroundService::class.java)
                                            .setAction(SessionForegroundService.actionStart)
                                    )
                                },
                                onSyncClipboard = {
                                    ContextCompat.startForegroundService(
                                        context,
                                        Intent(context, SessionForegroundService::class.java)
                                            .setAction(SessionForegroundService.actionSyncClipboard)
                                    )
                                },
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                    item {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(14.dp)
                        ) {
                            NativeInputCard(modifier = Modifier.weight(1f))
                            ClipboardHistoryCard(
                                history = history,
                                showHistory = showClipboardHistory,
                                onToggle = { showClipboardHistory = !showClipboardHistory },
                                onRecopy = { ClipboardHistoryStore.recopy(context, it) },
                                onDownload = { ClipboardHistoryStore.download(context, it) },
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                } else {
                    item {
                        PairingCard(
                            state = pairingState,
                            onPairingCodeChange = { PairingStore.updateEnteredCode(it) },
                            onGeneratePairingCode = { PairingStore.regeneratePairingCode() }
                        )
                    }
                    item {
                        TransportCard(
                            sessionState = sessionState,
                            onRestartServer = {
                                ContextCompat.startForegroundService(
                                    context,
                                    Intent(context, SessionForegroundService::class.java)
                                        .setAction(SessionForegroundService.actionStart)
                                )
                            },
                            onSyncClipboard = {
                                ContextCompat.startForegroundService(
                                    context,
                                    Intent(context, SessionForegroundService::class.java)
                                        .setAction(SessionForegroundService.actionSyncClipboard)
                                )
                            }
                        )
                    }
                    item {
                        NativeInputCard()
                    }
                    item {
                        ClipboardHistoryCard(
                            history = history,
                            showHistory = showClipboardHistory,
                            onToggle = { showClipboardHistory = !showClipboardHistory },
                            onRecopy = { ClipboardHistoryStore.recopy(context, it) },
                            onDownload = { ClipboardHistoryStore.download(context, it) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun NativeInputCard(modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = Panel)
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionTitle(title = "입력 조작", detail = "키보드와 포인터 방식")
            Text(
                text = "태블릿을 Mac의 터치 가능한 확장 디스플레이로 사용합니다.",
                color = Success,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = "Mac에서 확장 화면을 시작한 다음 이 태블릿을 터치해 Mac 앱을 조작하세요.",
                color = Muted
            )
        }
    }
}

@Composable
private fun StatusOverviewCard(sessionState: SessionRuntimeState) {
    Card(
        shape = RoundedCornerShape(30.dp),
        colors = CardDefaults.cardColors(containerColor = PanelStrong)
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionTitle(title = "연결 준비", detail = "수신 서버와 무선 검색 상태")
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                StatusTile(
                    label = "수신 서버",
                    value = sessionState.serviceState,
                    modifier = Modifier.weight(1f)
                )
                StatusTile(
                    label = "무선 검색",
                    value = sessionState.discoveryState,
                    modifier = Modifier.weight(1f)
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                StatusTile(
                    label = "Wi-Fi 주소",
                    value = sessionState.lanEndpoint,
                    modifier = Modifier.weight(1f)
                )
                StatusTile(
                    label = "연결된 Mac",
                    value = sessionState.peerDeviceName,
                    modifier = Modifier.weight(1f)
                )
            }
            Text(
                text = "Mac 앱에서 Wi-Fi 검색을 누른 뒤 이 갤럭시를 선택하세요. 검색이 막히면 여기에 표시된 IP 주소로 직접 연결하세요.",
                color = Muted,
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

@Composable
private fun StatusTile(label: String, value: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .background(Color(0xFFF7FAF8), RoundedCornerShape(18.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Text(
            text = label.uppercase(),
            color = Warm,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Black
        )
        Text(
            text = value,
            color = Ink,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
private fun SectionTitle(title: String, detail: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .background(SoftBlue, RoundedCornerShape(14.dp)),
            contentAlignment = Alignment.Center
        ) {
            Text(title.take(1), color = Accent, fontWeight = FontWeight.Black)
        }
        Column {
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge,
                color = Ink,
                fontWeight = FontWeight.Black
            )
            Text(
                text = detail,
                color = Muted,
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

@Composable
private fun HeaderCard() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                Brush.linearGradient(
                    colors = listOf(Color(0xFF173847), Color(0xFF315B63), Color(0xFFB96D4E))
                ),
                RoundedCornerShape(32.dp)
            )
    ) {
        Column(modifier = Modifier.padding(22.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                text = "MAC TO GALAXY",
                color = Color.White.copy(alpha = 0.74f),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Black
            )
            Text(
                text = "MtoG",
                style = MaterialTheme.typography.headlineMedium,
                color = Color.White,
                fontWeight = FontWeight.Black
            )
            Text(
                text = "Mac과 Galaxy, 하나의 작업 공간. USB로 연결하고 Mac에서 사용할 기능을 켜세요.",
                color = Color.White.copy(alpha = 0.84f),
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

@Composable
private fun PairingCard(
    state: PairingUiState,
    onPairingCodeChange: (String) -> Unit,
    onGeneratePairingCode: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = Panel)
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            SectionTitle(title = "페어링", detail = "4자리 코드로 신뢰 저장")
            Text(
                text = "아래 4자리 코드를 Mac 앱의 페어링 코드 칸에 입력하세요. 코드는 확인용이고, 실제 신뢰 키는 앱이 따로 안전하게 저장합니다.",
                color = Muted
            )
            Text(
                text = state.statusText,
                color = Ink,
                fontWeight = FontWeight.SemiBold
            )
            OutlinedTextField(
                value = state.enteredCode,
                onValueChange = onPairingCodeChange,
                label = { Text("4자리 코드") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = onGeneratePairingCode) {
                    Text("새 코드")
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                repeat(4) { index ->
                    DigitBox(digit = state.enteredCode.getOrNull(index)?.toString().orEmpty())
                }
            }
            Text(
                text = "저장된 기기: ${state.trustedPeerCount}개 · 최근 기기: ${state.lastTrustedPeerName}",
                color = Muted
            )
        }
    }
}

@Composable
private fun DigitBox(digit: String) {
    Box(
        modifier = Modifier
            .size(width = 72.dp, height = 84.dp)
            .background(PanelStrong, RoundedCornerShape(20.dp)),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = if (digit.isEmpty()) "•" else digit,
            style = MaterialTheme.typography.headlineMedium,
            color = Accent,
            fontWeight = FontWeight.Bold
        )
    }
}

@Composable
private fun TransportCard(
    sessionState: SessionRuntimeState,
    onRestartServer: () -> Unit,
    onSyncClipboard: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = Panel)
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionTitle(title = "연결 및 수동 전송", detail = "실제 수신 상태")
            Text(sessionState.serviceState, color = Ink,
                style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(sessionState.peerDeviceName, color = Muted)
            Text(sessionState.lastClipboardEvent, color = Muted)
            sessionState.lastError?.let { error ->
                Text(
                    text = error,
                    color = Color(0xFF9F3A2A),
                    fontWeight = FontWeight.SemiBold
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onRestartServer, modifier = Modifier.fillMaxWidth()) {
                    Text("연결 대기 시작 / 다시 연결")
                }
                Button(onClick = onSyncClipboard, modifier = Modifier.fillMaxWidth()) {
                    Text("현재 클립보드를 Mac으로 보내기")
                }
            }
            var showDiagnostics by remember { mutableStateOf(false) }
            androidx.compose.material3.TextButton(onClick = { showDiagnostics = !showDiagnostics }) {
                Text(if (showDiagnostics) "연결 진단 접기" else "연결 진단 보기")
            }
            if (showDiagnostics) {
                InfoLine(label = "Wi-Fi 주소", value = sessionState.lanEndpoint)
                InfoLine(label = "검색", value = sessionState.discoveryState)
                InfoLine(label = "최근 수신", value = sessionState.lastInboundType)
                InfoLine(label = "최근 송신", value = sessionState.lastOutboundType)
                Text("Wi-Fi 수동 전송은 같은 개인 네트워크에서 사용하세요. 자동 텍스트와 확장 화면은 USB로 연결하세요.", color = Muted)
            }
        }
    }
}

@Composable
private fun InfoLine(label: String, value: String, strong: Boolean = false) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(PanelStrong, RoundedCornerShape(16.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label.uppercase(),
            color = Warm,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Black
        )
        Spacer(modifier = Modifier.width(16.dp))
        Text(
            modifier = Modifier.weight(1f),
            text = value,
            color = if (strong) Ink else Muted,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = if (strong) FontWeight.Bold else FontWeight.SemiBold
        )
    }
}

@Composable
private fun ClipboardHistoryCard(
    history: List<ClipboardHistoryRecord>,
    showHistory: Boolean,
    onToggle: () -> Unit,
    onRecopy: (ClipboardHistoryRecord) -> Unit,
    onDownload: (ClipboardHistoryRecord) -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = Panel)
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionTitle(title = "클립보드 기록", detail = "동기화한 항목")
                Spacer(modifier = Modifier.weight(1f))
                Button(onClick = onToggle) {
                    Text(if (showHistory) "숨기기" else "보기")
                }
            }
            Text(
                text = "텍스트와 파일명은 글자로, 이미지는 작은 미리보기로 표시합니다. 다시 복사는 갤럭시 클립보드에 다시 넣고, 저장은 기기에 파일로 저장합니다.",
                color = Muted,
                fontWeight = FontWeight.SemiBold
            )
            if (showHistory) {
                if (history.isEmpty()) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(PanelStrong, RoundedCornerShape(18.dp))
                            .padding(18.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text("아직 클립보드 기록이 없습니다", color = Muted, fontWeight = FontWeight.SemiBold)
                    }
                } else {
                    history.forEach { item ->
                        HistoryRow(
                            item = item,
                            onRecopy = { onRecopy(item) },
                            onDownload = { onDownload(item) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun HistoryRow(
    item: ClipboardHistoryRecord,
    onRecopy: () -> Unit,
    onDownload: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(PanelStrong, RoundedCornerShape(20.dp))
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        HistoryPreview(item = item)

        Column(
            modifier = Modifier
                .padding(start = 14.dp)
                .weight(1f)
        ) {
            Text(item.title, color = Ink, fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.height(2.dp))
            Text(item.detail, color = Muted, style = MaterialTheme.typography.bodySmall)
            Text("${item.timestamp} · ${item.size}", color = Warm, style = MaterialTheme.typography.bodySmall)
        }

        Column(
            modifier = Modifier.width(104.dp),
            horizontalAlignment = Alignment.End,
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Button(
                onClick = onRecopy,
                enabled = item.canReCopy,
                modifier = Modifier
                    .fillMaxWidth()
            ) {
                Text("다시 복사")
            }
            Button(
                onClick = onDownload,
                enabled = item.canReCopy,
                modifier = Modifier
                    .fillMaxWidth()
            ) {
                Text("저장")
            }
        }
    }
}

@Composable
private fun HistoryPreview(item: ClipboardHistoryRecord) {
    val bitmap = remember(item.filePath) {
        if (item.kind == "image" && item.filePath != null) {
            BitmapFactory.decodeFile(item.filePath)
        } else {
            null
        }
    }
    if (bitmap != null) {
        Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = item.title,
            modifier = Modifier
                .size(48.dp)
                .clip(RoundedCornerShape(14.dp)),
            contentScale = ContentScale.Crop
        )
    } else {
        Box(
            modifier = Modifier
                .size(48.dp)
                .background(SoftBlue, RoundedCornerShape(14.dp)),
            contentAlignment = Alignment.Center
        ) {
            Text(text = item.kindBadge, color = Accent, fontWeight = FontWeight.Bold)
        }
    }
}
