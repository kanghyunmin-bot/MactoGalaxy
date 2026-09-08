package com.mtog.app.externaldisplay

import android.graphics.RectF
import android.os.SystemClock
import android.view.MotionEvent
import com.mtog.core.GestureCommand
import com.mtog.core.GestureEvent
import com.mtog.core.GestureStateMachine
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
import java.util.UUID

class ExternalDisplayTouchController(
    private val scope: CoroutineScope,
    private val controlSessionID: UUID
) {
    private val messages = Channel<String>(128, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    private val machine = GestureStateMachine()
    private val stateLock = Any()
    @Volatile private var enabled = true
    private var clientJob: Job? = null
    @Volatile private var clientSocket: Socket? = null
    private var timerJob: Job? = null
    private var active = false
    private var lastX = 0.5
    private var lastY = 0.5
    private var sequence = 0L

    fun start(port: Int) {
        clientJob = scope.launch(Dispatchers.IO) {
            while (isActive) {
                while (messages.tryReceive().isSuccess) Unit
                try {
                    Socket(InetAddress.getByName("127.0.0.1"), port).use { socket ->
                        clientSocket = socket
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
                } finally {
                    clientSocket = null
                }
            }
        }
    }

    fun setEnabled(enabled: Boolean) {
        if (this.enabled && !enabled) cancelGesture()
        this.enabled = enabled
    }

    fun stop() {
        cancelGesture()
        timerJob?.cancel()
        runCatching { clientSocket?.close() }
        clientSocket = null
        clientJob?.cancel()
        messages.close()
    }

    fun handle(event: MotionEvent, rect: RectF): Boolean {
        if (!enabled || rect.width() <= 0 || rect.height() <= 0) return false
        val centroid = centroid(event)
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            active = rect.contains(centroid.first, centroid.second)
        }
        if (!active) return false

        val x = ((centroid.first - rect.left) / rect.width()).coerceIn(0f, 1f).toDouble()
        val y = ((centroid.second - rect.top) / rect.height()).coerceIn(0f, 1f).toDouble()
        lastX = x
        lastY = y
        val kind = actionName(event.actionMasked) ?: return false
        emit(machineEvent(kind, event.eventTime, event.pointerCount, x, y))

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                timerJob?.cancel()
                scheduleTick(GestureStateMachine.longPressDelayMs + 1)
            }
            MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_POINTER_UP -> timerJob?.cancel()
            MotionEvent.ACTION_UP -> {
                timerJob?.cancel()
                scheduleTick(GestureStateMachine.doubleTapDelayMs + 1)
                active = false
            }
            MotionEvent.ACTION_CANCEL -> {
                timerJob?.cancel()
                active = false
            }
        }
        return true
    }

    private fun scheduleTick(delayMs: Long) {
        timerJob = scope.launch {
            delay(delayMs)
            emit(machineEvent("tick", SystemClock.uptimeMillis(), if (active) 1 else 0, lastX, lastY))
        }
    }

    private fun cancelGesture() {
        timerJob?.cancel()
        emit(machineEvent("cancel", SystemClock.uptimeMillis(), 1, lastX, lastY))
        active = false
    }

    private fun machineEvent(kind: String, timeMs: Long, pointers: Int, x: Double, y: Double) =
        GestureEvent(kind, timeMs, pointers, x, y)

    private fun emit(event: GestureEvent) {
        val commands = synchronized(stateLock) { machine.process(event) }
        commands.forEach(::enqueue)
    }

    private fun enqueue(command: GestureCommand) {
        val json = JSONObject()
            .put("type", "gestureCommand")
            .put("sessionId", controlSessionID.toString())
            .put("sequence", synchronized(stateLock) { ++sequence })
            .put("kind", command.kind)
        command.x?.let { json.put("x", it) }
        command.y?.let { json.put("y", it) }
        command.deltaX?.let { json.put("deltaX", it) }
        command.deltaY?.let { json.put("deltaY", it) }
        command.button?.let { json.put("button", it) }
        command.tapCount?.let { json.put("tapCount", it) }
        messages.trySend(json.toString())
    }

    private fun centroid(event: MotionEvent): Pair<Float, Float> {
        var x = 0f
        var y = 0f
        repeat(event.pointerCount) { x += event.getX(it); y += event.getY(it) }
        return x / event.pointerCount to y / event.pointerCount
    }

    private fun actionName(action: Int): String? = when (action) {
        MotionEvent.ACTION_DOWN -> "down"
        MotionEvent.ACTION_POINTER_DOWN -> "pointerDown"
        MotionEvent.ACTION_MOVE -> "move"
        MotionEvent.ACTION_POINTER_UP -> "pointerUp"
        MotionEvent.ACTION_UP -> "up"
        MotionEvent.ACTION_CANCEL -> "cancel"
        else -> null
    }
}
