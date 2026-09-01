package com.mtog.app.externaldisplay

import android.graphics.RectF
import android.os.SystemClock
import android.view.MotionEvent
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.BufferedWriter
import java.io.OutputStreamWriter
import java.net.InetAddress
import java.net.Socket
import kotlin.math.hypot
import kotlin.math.min

class ExternalDisplayTouchController(private val scope: CoroutineScope) {
    private val messages = Channel<String>(128, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    @Volatile private var enabled = true
    private var clientJob: Job? = null
    private var longPressJob: Job? = null
    private var active = false
    private var downX = 0f
    private var downY = 0f
    private var downTime = 0L
    private var moved = false
    private var longPressSent = false
    private var lastTapTime = 0L
    private var lastTapX = 0f
    private var lastTapY = 0f

    fun start(port: Int) {
        clientJob = scope.launch(Dispatchers.IO) {
            while (isActive) {
                while (messages.tryReceive().isSuccess) Unit
                try {
                    Socket(InetAddress.getByName("127.0.0.1"), port).use { socket ->
                        socket.tcpNoDelay = true
                        val writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8))
                        while (isActive && !socket.isClosed) {
                            writer.write(messages.receive())
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

    fun setEnabled(enabled: Boolean) {
        this.enabled = enabled
        if (!enabled) longPressJob?.cancel()
    }

    fun stop() {
        longPressJob?.cancel()
        clientJob?.cancel()
        messages.close()
    }

    fun handle(event: MotionEvent, rect: RectF): Boolean {
        if (!enabled) return false
        if (rect.width() <= 0 || rect.height() <= 0) return false
        val action = actionName(event.actionMasked) ?: return false
        val centroid = centroid(event)
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            active = rect.contains(centroid.first, centroid.second)
            downX = centroid.first
            downY = centroid.second
            downTime = SystemClock.uptimeMillis()
            moved = false
            longPressSent = false
        }
        if (!active) return false
        val x = ((centroid.first - rect.left) / rect.width()).coerceIn(0f, 1f)
        val y = ((centroid.second - rect.top) / rect.height()).coerceIn(0f, 1f)
        val span = normalizedSpan(event, rect)
        enqueue(action, event.pointerCount, x, y, span)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> startLongPress(x, y, span)
            MotionEvent.ACTION_MOVE -> {
                if (event.pointerCount != 1 || hypot(centroid.first - downX, centroid.second - downY) > 56f) {
                    moved = true
                    longPressJob?.cancel()
                }
            }
            MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_POINTER_UP -> {
                moved = true
                longPressJob?.cancel()
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                longPressJob?.cancel()
                if (event.actionMasked == MotionEvent.ACTION_UP) maybeDoubleTap(x, y, centroid.first, centroid.second)
                active = false
            }
        }
        return true
    }

    private fun startLongPress(x: Float, y: Float, span: Float) {
        longPressJob?.cancel()
        longPressJob = scope.launch {
            delay(1_000)
            if (active) {
                longPressSent = true
                enqueue("right_click", 1, x, y, span)
            }
        }
    }

    private fun maybeDoubleTap(x: Float, y: Float, screenX: Float, screenY: Float) {
        val now = SystemClock.uptimeMillis()
        if (moved || longPressSent || now - downTime > 650) {
            lastTapTime = 0
            return
        }
        if (now - lastTapTime <= 700 && hypot(screenX - lastTapX, screenY - lastTapY) <= 96f) {
            enqueue("click", 1, x, y, 0f)
            lastTapTime = 0
        } else {
            lastTapTime = now
            lastTapX = screenX
            lastTapY = screenY
        }
    }

    private fun enqueue(action: String, pointers: Int, x: Float, y: Float, span: Float) {
        messages.trySend(
            JSONObject().put("type", "touch").put("action", action).put("pointers", pointers)
                .put("x", x.toDouble()).put("y", y.toDouble()).put("span", span.toDouble()).toString()
        )
    }

    private fun centroid(event: MotionEvent): Pair<Float, Float> {
        var x = 0f
        var y = 0f
        repeat(event.pointerCount) { x += event.getX(it); y += event.getY(it) }
        return x / event.pointerCount to y / event.pointerCount
    }

    private fun normalizedSpan(event: MotionEvent, rect: RectF): Float {
        if (event.pointerCount < 2) return 0f
        return (hypot(event.getX(0) - event.getX(1), event.getY(0) - event.getY(1)) /
            min(rect.width(), rect.height()).coerceAtLeast(1f)).coerceIn(0f, 2f)
    }

    private fun actionName(action: Int): String? = when (action) {
        MotionEvent.ACTION_DOWN -> "down"
        MotionEvent.ACTION_POINTER_DOWN -> "pointer_down"
        MotionEvent.ACTION_MOVE -> "move"
        MotionEvent.ACTION_POINTER_UP -> "pointer_up"
        MotionEvent.ACTION_UP -> "up"
        MotionEvent.ACTION_CANCEL -> "cancel"
        else -> null
    }
}
