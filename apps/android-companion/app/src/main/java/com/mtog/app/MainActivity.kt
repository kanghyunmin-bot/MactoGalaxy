package com.mtog.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Build
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
import com.mtog.app.transport.TransportCoordinator
import com.mtog.app.transport.TransportMode
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
        requestNotificationPermissionIfNeeded()
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

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 46002)
    }
}

@Composable
private fun HomeScreen() {
    val context = LocalContext.current
    val coordinator = remember { TransportCoordinator() }
    var mode by remember { mutableStateOf(coordinator.mode) }
    val sessionState by SessionRuntime.state.collectAsState()
    val history by ClipboardHistoryStore.history.collectAsState()
    val pairingState by PairingStore.state.collectAsState()
    var showClipboardHistory by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        ClipboardHistoryStore.initialize(context)
        PairingStore.initialize(context)
        ContextCompat.startForegroundService(
            context,
            Intent(context, SessionForegroundService::class.java).setAction(SessionForegroundService.actionStart)
        )
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
        LazyColumn(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            item {
                HeaderCard()
            }
            item {
                PairingCard(
                    state = pairingState,
                    onPairingCodeChange = { PairingStore.updateEnteredCode(it) }
                )
            }
            item {
                TransportCard(
                    mode = mode,
                    sessionState = sessionState,
                    onRotate = { mode = coordinator.rotateMode() },
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

@Composable
private fun NativeInputCard() {
    Card(
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = Panel)
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionTitle(title = "Native Input", detail = "Input architecture")
            Text(
                text = "Accessibility gesture injection is disabled for normal control.",
                color = Success,
                fontWeight = FontWeight.SemiBold
            )
            Text(
                text = "Use USB AOA HID for edge control. Mirror mode is window-local so Mac control returns as soon as the pointer leaves the mirror window.",
                color = Muted
            )
        }
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
                text = "Manual clipboard handoff, trusted listener, and window-local mirror control for Galaxy Tab.",
                color = Color.White.copy(alpha = 0.84f),
                fontWeight = FontWeight.SemiBold
            )
        }
    }
}

@Composable
private fun PairingCard(
    state: PairingUiState,
    onPairingCodeChange: (String) -> Unit
) {
    Card(
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = Panel)
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            SectionTitle(title = "Pairing", detail = "4-digit trust confirmation")
            Text(
                text = "Enter the same 4-digit code on both devices. This is only the human confirmation step; trust keys are stored separately.",
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
                label = { Text("4-digit code") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                repeat(4) { index ->
                    DigitBox(digit = state.enteredCode.getOrNull(index)?.toString().orEmpty())
                }
            }
            Text(
                text = "Trusted peers saved: ${state.trustedPeerCount} · Last trusted: ${state.lastTrustedPeerName}",
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
    mode: TransportMode,
    sessionState: SessionRuntimeState,
    onRotate: () -> Unit,
    onRestartServer: () -> Unit,
    onSyncClipboard: () -> Unit
) {
    Card(
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = Panel)
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            SectionTitle(title = "Transport", detail = "USB dev, wireless, manual clipboard")
            Text(
                text = mode.label,
                color = Ink,
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Black
            )
            Text(
                text = mode.detail,
                color = Muted
            )
            InfoLine(label = "Listener", value = sessionState.serviceState, strong = true)
            InfoLine(label = "Peer", value = sessionState.peerDeviceName)
            InfoLine(label = "Wireless", value = sessionState.lanEndpoint, strong = true)
            InfoLine(label = "Traffic", value = "Inbound ${sessionState.lastInboundType} · Outbound ${sessionState.lastOutboundType}")
            InfoLine(label = "Control", value = sessionState.lastControlEvent)
            InfoLine(label = "Clipboard", value = sessionState.lastClipboardEvent)
            Text(
                text = "Automatic clipboard watching is disabled. For Galaxy→Mac sync, copy on Galaxy and tap the notification action: Sync Clipboard.",
                color = Muted
            )
            sessionState.lastError?.let { error ->
                Text(
                    text = error,
                    color = Color(0xFF9F3A2A),
                    fontWeight = FontWeight.SemiBold
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = onRestartServer) {
                    Text("Show Notification")
                }
                Button(onClick = onSyncClipboard) {
                    Text("Sync Now")
                }
                Button(onClick = onRotate) {
                    Text("Cycle Demo Mode")
                }
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
        Spacer(modifier = Modifier.weight(1f))
        Text(
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
    onDownload: (ClipboardHistoryRecord) -> Unit
) {
    Card(
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = Panel)
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionTitle(title = "Clipboard History", detail = "Manual sync items")
                Spacer(modifier = Modifier.weight(1f))
                Button(onClick = onToggle) {
                    Text(if (showHistory) "Hide" else "Show")
                }
            }
            Text(
                text = "Text and file names stay text-only. Images show a small preview. Use Re-copy to put an item back on the Galaxy clipboard, or Download to save it.",
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
                        Text("No clipboard history yet", color = Muted, fontWeight = FontWeight.SemiBold)
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
                Text("Re-copy")
            }
            Button(
                onClick = onDownload,
                enabled = item.canReCopy,
                modifier = Modifier
                    .fillMaxWidth()
            ) {
                Text("Download")
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
