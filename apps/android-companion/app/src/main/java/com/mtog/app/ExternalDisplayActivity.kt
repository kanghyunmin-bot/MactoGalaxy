package com.mtog.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.RectF
import android.os.Bundle
import android.os.SystemClock
import android.view.MotionEvent
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import com.mtog.app.ui.theme.MtoGTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedWriter
import java.io.OutputStreamWriter
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import kotlin.math.hypot
import kotlin.math.min

class ExternalDisplayActivity : ComponentActivity() {
    private var serverSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    private val touchInputMessages = Channel<String>(
        capacity = 128,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
    private var touchInputJob: Job? = null
    @Volatile private var latestFrameWidth: Int = 1920
    @Volatile private var latestFrameHeight: Int = 1200
    private var externalTouchActive = false
    private var longPressJob: Job? = null
    private var longPressStartX = 0f
    private var longPressStartY = 0f
    private var touchDownTimeMs = 0L
    private var touchMoved = false
    private var longPressSent = false
    private var lastTapTimeMs = 0L
    private var lastTapX = 0f
    private var lastTapY = 0f
    private val longPressDelayMs = 1_000L
    private val longPressMoveTolerancePx = 56f
    private val doubleTapIntervalMs = 700L
    private val doubleTapDistancePx = 96f
    private val tapMaxDurationMs = 650L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).hide(WindowInsetsCompat.Type.systemBars())

        val port = intent.getIntExtra("port", 46002)
        val inputPort = intent.getIntExtra("inputPort", 46003)
        startTouchInputClient(inputPort)
        setContent {
            MtoGTheme {
                ExternalDisplayScreen(
                    port = port,
                    receiver = ::receiveFrames
                )
            }
        }
    }

    override fun onDestroy() {
        longPressJob?.cancel()
        touchInputJob?.cancel()
        touchInputMessages.close()
        clientSocket?.close()
        serverSocket?.close()
        super.onDestroy()
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (emitExternalDisplayTouch(event)) {
            return true
        }
        return super.dispatchTouchEvent(event)
    }

    private fun startTouchInputClient(port: Int) {
        touchInputJob = lifecycleScope.launch(Dispatchers.IO) {
            while (isActive) {
                drainStaleTouchMessages()
                try {
                    Socket(InetAddress.getByName("127.0.0.1"), port).use { socket ->
                        socket.tcpNoDelay = true
                        val writer = BufferedWriter(
                            OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8)
                        )
                        while (isActive && !socket.isClosed) {
                            val message = touchInputMessages.receive()
                            writer.write(message)
                            writer.newLine()
                            writer.flush()
                        }
                    }
                } catch (_: Throwable) {
                    delay(250)
                }
            }
        }
    }

    private fun drainStaleTouchMessages() {
        while (touchInputMessages.tryReceive().isSuccess) {
            // Drop touch samples captured before the Mac-side input channel is ready.
        }
    }

    private fun emitExternalDisplayTouch(event: MotionEvent): Boolean {
        val root = window.decorView
        val viewWidth = root.width
        val viewHeight = root.height
        if (viewWidth <= 0 || viewHeight <= 0) {
            return false
        }

        val rect = contentRect(viewWidth, viewHeight)
        val action = touchActionName(event.actionMasked) ?: return false
        val centroid = touchCentroid(event)
        val insideFrame = rect.contains(centroid.first, centroid.second)

        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            externalTouchActive = insideFrame
            longPressStartX = centroid.first
            longPressStartY = centroid.second
            touchDownTimeMs = SystemClock.uptimeMillis()
            touchMoved = false
            longPressSent = false
        }
        if (!externalTouchActive) {
            return false
        }

        val normalizedX = ((centroid.first - rect.left) / rect.width()).coerceIn(0f, 1f)
        val normalizedY = ((centroid.second - rect.top) / rect.height()).coerceIn(0f, 1f)
        val span = normalizedSpan(event, rect)
        enqueueTouch(action, event.pointerCount, normalizedX, normalizedY, span)

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                startLongPressTimer(normalizedX, normalizedY, span)
            }
            MotionEvent.ACTION_MOVE -> {
                val moved = hypot(
                    centroid.first - longPressStartX,
                    centroid.second - longPressStartY
                )
                if (event.pointerCount != 1 || moved > longPressMoveTolerancePx) {
                    touchMoved = true
                    longPressJob?.cancel()
                }
            }
            MotionEvent.ACTION_POINTER_DOWN,
            MotionEvent.ACTION_POINTER_UP -> {
                touchMoved = true
                longPressJob?.cancel()
            }
        }

        if (
            event.actionMasked == MotionEvent.ACTION_UP ||
            event.actionMasked == MotionEvent.ACTION_CANCEL
        ) {
            longPressJob?.cancel()
            if (event.actionMasked == MotionEvent.ACTION_UP) {
                maybeEmitDoubleTapClick(normalizedX, normalizedY, centroid.first, centroid.second)
            }
            externalTouchActive = false
        }
        return true
    }

    private fun startLongPressTimer(normalizedX: Float, normalizedY: Float, span: Float) {
        longPressJob?.cancel()
        longPressJob = lifecycleScope.launch {
            delay(longPressDelayMs)
            if (externalTouchActive) {
                longPressSent = true
                enqueueTouch(
                    action = "right_click",
                    pointerCount = 1,
                    normalizedX = normalizedX,
                    normalizedY = normalizedY,
                    span = span
                )
            }
        }
    }

    private fun maybeEmitDoubleTapClick(
        normalizedX: Float,
        normalizedY: Float,
        screenX: Float,
        screenY: Float
    ) {
        val now = SystemClock.uptimeMillis()
        val duration = now - touchDownTimeMs
        if (touchMoved || longPressSent || duration > tapMaxDurationMs) {
            lastTapTimeMs = 0L
            return
        }

        val distanceFromLastTap = hypot(screenX - lastTapX, screenY - lastTapY)
        if (now - lastTapTimeMs <= doubleTapIntervalMs && distanceFromLastTap <= doubleTapDistancePx) {
            enqueueTouch(
                action = "click",
                pointerCount = 1,
                normalizedX = normalizedX,
                normalizedY = normalizedY,
                span = 0f
            )
            lastTapTimeMs = 0L
        } else {
            lastTapTimeMs = now
            lastTapX = screenX
            lastTapY = screenY
        }
    }

    private fun enqueueTouch(
        action: String,
        pointerCount: Int,
        normalizedX: Float,
        normalizedY: Float,
        span: Float
    ) {
        val payload = JSONObject()
            .put("type", "touch")
            .put("action", action)
            .put("pointers", pointerCount)
            .put("x", normalizedX.toDouble())
            .put("y", normalizedY.toDouble())
            .put("span", span.toDouble())

        touchInputMessages.trySend(payload.toString())
    }

    private fun contentRect(viewWidth: Int, viewHeight: Int): RectF {
        val frameWidth = latestFrameWidth.coerceAtLeast(1)
        val frameHeight = latestFrameHeight.coerceAtLeast(1)
        val scale = min(
            viewWidth.toFloat() / frameWidth.toFloat(),
            viewHeight.toFloat() / frameHeight.toFloat()
        )
        val drawWidth = frameWidth * scale
        val drawHeight = frameHeight * scale
        val left = (viewWidth - drawWidth) / 2f
        val top = (viewHeight - drawHeight) / 2f
        return RectF(left, top, left + drawWidth, top + drawHeight)
    }

    private fun touchCentroid(event: MotionEvent): Pair<Float, Float> {
        var x = 0f
        var y = 0f
        for (index in 0 until event.pointerCount) {
            x += event.getX(index)
            y += event.getY(index)
        }
        return Pair(x / event.pointerCount, y / event.pointerCount)
    }

    private fun normalizedSpan(event: MotionEvent, rect: RectF): Float {
        if (event.pointerCount < 2) {
            return 0f
        }
        val dx = event.getX(0) - event.getX(1)
        val dy = event.getY(0) - event.getY(1)
        val denominator = min(rect.width(), rect.height()).coerceAtLeast(1f)
        return (hypot(dx, dy) / denominator).coerceIn(0f, 2f)
    }

    private fun touchActionName(action: Int): String? = when (action) {
        MotionEvent.ACTION_DOWN -> "down"
        MotionEvent.ACTION_POINTER_DOWN -> "pointer_down"
        MotionEvent.ACTION_MOVE -> "move"
        MotionEvent.ACTION_POINTER_UP -> "pointer_up"
        MotionEvent.ACTION_UP -> "up"
        MotionEvent.ACTION_CANCEL -> "cancel"
        else -> null
    }

    private suspend fun receiveFrames(
        port: Int,
        onStatus: suspend (String) -> Unit,
        onFrame: suspend (Bitmap) -> Unit
    ) = withContext(Dispatchers.IO) {
        try {
            reportStatus("Waiting for Mac external display stream on USB", onStatus)
            serverSocket = ServerSocket(port, 1, InetAddress.getByName("127.0.0.1"))
            clientSocket = serverSocket?.accept()
            val socket = clientSocket ?: return@withContext
            socket.tcpNoDelay = true
            reportStatus("Mac stream connected", onStatus)

            val input = BufferedInputStream(socket.getInputStream())
            val greeting = input.readExact(8)
            if (String(greeting) != "MTOGVD1\n") {
                reportStatus("Invalid external display stream", onStatus)
                return@withContext
            }

            while (isActive) {
                val magic = input.readExact(4)
                if (String(magic) != "FRAM") {
                    reportStatus("External display stream lost", onStatus)
                    return@withContext
                }

                val length = ByteBuffer.wrap(input.readExact(4)).int
                if (length <= 0 || length > 8 * 1024 * 1024) {
                    reportStatus("External display frame rejected", onStatus)
                    return@withContext
                }

                val bytes = input.readExact(length)
                val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                if (bitmap != null) {
                    latestFrameWidth = bitmap.width
                    latestFrameHeight = bitmap.height
                    withContext(Dispatchers.Main) {
                        onFrame(bitmap)
                    }
                }
            }
        } catch (error: Throwable) {
            reportStatus("External display stopped: ${error.message ?: error.javaClass.simpleName}", onStatus)
        } finally {
            clientSocket?.close()
            clientSocket = null
            serverSocket?.close()
            serverSocket = null
        }
    }

    private suspend fun reportStatus(
        message: String,
        onStatus: suspend (String) -> Unit
    ) {
        withContext(Dispatchers.Main) {
            onStatus(message)
        }
    }

    private fun BufferedInputStream.readExact(size: Int): ByteArray {
        val output = ByteArray(size)
        var offset = 0
        while (offset < size) {
            val read = read(output, offset, size - offset)
            if (read < 0) {
                throw IllegalStateException("socket closed")
            }
            offset += read
        }
        return output
    }
}

@Composable
private fun ExternalDisplayScreen(
    port: Int,
    receiver: suspend (
        Int,
        suspend (String) -> Unit,
        suspend (Bitmap) -> Unit
    ) -> Unit
) {
    var status by remember { mutableStateOf("Preparing Galaxy external display") }
    var frame by remember { mutableStateOf<Bitmap?>(null) }

    LaunchedEffect(port) {
        receiver(
            port,
            { nextStatus -> status = nextStatus },
            { bitmap -> frame = bitmap }
        )
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black),
        contentAlignment = Alignment.Center
    ) {
        val bitmap = frame
        if (bitmap != null) {
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = "Mac external display",
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Fit
            )
        } else {
            Column(
                modifier = Modifier
                    .background(Color(0xCC101820), RoundedCornerShape(28.dp))
                    .padding(horizontal = 28.dp, vertical = 22.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = "MtoG External Display",
                    style = MaterialTheme.typography.headlineSmall,
                    color = Color.White,
                    fontWeight = FontWeight.Black
                )
                Text(
                    text = status,
                    color = Color.White.copy(alpha = 0.78f),
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}
