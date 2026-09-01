package com.mtog.app.externaldisplay

import android.os.SystemClock
import android.view.Surface
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.mtog.core.VideoCodec
import com.mtog.core.VideoPacket
import com.mtog.core.VideoPacketKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicLong

data class ExternalDisplayUiState(
    val status: String = "Mac 외장 화면을 기다리는 중",
    val decoderState: DecoderState = DecoderState.WaitingSurface,
    val codec: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val framesPerSecond: Int? = null,
    val bitrateBitsPerSecond: Long? = null,
    val queueDepth: Int = 0,
    val droppedFrames: Long = 0,
    val lastFrameTimeMs: Long? = null
)

class ExternalDisplayViewModel(private val port: Int) : ViewModel() {
    private val receiver = VideoStreamReceiver(port)
    private val decoder = MediaCodecVideoDecoder()
    private val machine = DecoderStateMachine()
    private val mutex = Mutex()
    private val _state = MutableStateFlow(ExternalDisplayUiState())
    val state: StateFlow<ExternalDisplayUiState> = _state

    private var currentSurface: Surface? = null
    @Volatile private var paused = false
    private val lifecycleGeneration = AtomicLong()
    private var lastPacket: VideoPacket? = null
    private var frameWindowStartMs = SystemClock.elapsedRealtime()
    private var framesInWindow = 0
    private var bytesInWindow = 0L

    init {
        decoder.frameRenderedHandler = { generation ->
            viewModelScope.launch(Dispatchers.IO) {
                mutex.withLock {
                    if (!decoder.isGenerationActive(generation)) return@withLock
                    machine.onFrameRendered()
                    framesInWindow += 1
                    updateFrameMetrics()
                    publishState(null)
                }
            }
        }
        viewModelScope.launch(Dispatchers.IO) {
            _state.update { it.copy(status = "USB MTGV 스트림 수신 대기 중") }
            try {
                receiver.run(
                    onConnected = {
                        mutex.withLock {
                            resetMetrics("MTGV 연결됨 · codec config 대기 중", clearIdentity = true)
                            publishState(null)
                        }
                    },
                    onDisconnected = {
                        mutex.withLock {
                            execute(machine.onDisconnected())
                            resetMetrics("송신 재연결 대기 중", clearIdentity = true)
                            publishState(null)
                        }
                    },
                    onPacket = ::onPacket
                )
            } catch (error: Throwable) {
                machine.fail()
                _state.update {
                    it.copy(
                        status = "외장 화면 오류: ${error.message ?: error.javaClass.simpleName}",
                        decoderState = DecoderState.Failed
                    )
                }
            }
        }
    }

    fun onSurfaceAvailable(surface: Surface) {
        currentSurface = surface
        if (paused) return
        viewModelScope.launch(Dispatchers.IO) {
            mutex.withLock {
                decoder.setSurface(surface)
                execute(machine.onSurfaceAvailable())
                publishState("Surface 준비됨")
            }
        }
    }

    fun onSurfaceLost() {
        currentSurface = null
        viewModelScope.launch(Dispatchers.IO) {
            mutex.withLock {
                execute(machine.onSurfaceLost())
                decoder.setSurface(null)
                publishState("Surface 다시 생성 대기 중")
            }
        }
    }

    fun pause() {
        paused = true
        val generation = lifecycleGeneration.incrementAndGet()
        viewModelScope.launch(Dispatchers.IO) {
            mutex.withLock {
                if (generation != lifecycleGeneration.get()) return@withLock
                execute(machine.onSurfaceLost())
                decoder.setSurface(null)
                publishState("일시 중지됨")
            }
        }
    }

    fun resume() {
        paused = false
        val generation = lifecycleGeneration.incrementAndGet()
        val surface = currentSurface ?: return
        viewModelScope.launch(Dispatchers.IO) {
            mutex.withLock {
                if (generation != lifecycleGeneration.get()) return@withLock
                decoder.setSurface(surface)
                execute(machine.onSurfaceAvailable())
                publishState("Surface 복구 중")
            }
        }
    }

    private suspend fun onPacket(packet: VideoPacket) {
        mutex.withLock {
            lastPacket = packet
            bytesInWindow += packet.payload.size
            if (packet.kind == VideoPacketKind.Config) {
                resetMetrics("${packet.codec.displayName} 협상 완료 · 디코더 준비 중", clearIdentity = false)
                _state.update {
                    it.copy(codec = packet.codec.displayName, width = packet.width, height = packet.height)
                }
            }
            if (!paused || packet.kind == VideoPacketKind.Config) {
                val command = machine.onPacket(packet)
                if (!paused) execute(command)
            }
            publishState(null)
        }
    }

    private fun execute(command: DecoderCommand) {
        when (command) {
            is DecoderCommand.Configure -> configure(command.packet, reset = false)
            is DecoderCommand.ResetAndConfigure -> configure(command.packet, reset = true)
            is DecoderCommand.Decode -> when (val result = decoder.decode(command.packet)) {
                DecoderFeedResult.InputUnavailable -> {
                    machine.markFrameDropped()
                    receiver.requestKeyframe(command.packet)
                    _state.update { it.copy(status = "디코더 입력 대기 · 키프레임 요청", droppedFrames = it.droppedFrames + 1) }
                }
                DecoderFeedResult.Queued -> Unit
            }
            DecoderCommand.Reset -> decoder.reset()
            DecoderCommand.Stop -> decoder.stop()
            DecoderCommand.RequestKeyframe -> {
                lastPacket?.let(receiver::requestKeyframe)
                _state.update { it.copy(status = "키프레임 복구 요청", droppedFrames = it.droppedFrames + 1) }
            }
            DecoderCommand.Reject -> _state.update { it.copy(droppedFrames = it.droppedFrames + 1) }
            DecoderCommand.None -> Unit
        }
    }

    private fun configure(packet: VideoPacket, reset: Boolean) {
        try {
            if (reset) decoder.reset()
            decoder.configure(packet)
            machine.onConfigured()
        } catch (error: Throwable) {
            val fallback = machine.requestFallback(packet.codec)
            if (fallback == VideoCodec.H264) {
                receiver.requestH264Fallback(packet)
                _state.update { it.copy(status = "HEVC 실패 · H.264 재협상 요청", decoderState = DecoderState.Recovering) }
            } else {
                machine.fail()
                _state.update { it.copy(status = "디코더 오류: ${error.message}", decoderState = DecoderState.Failed) }
            }
        }
    }

    private fun updateFrameMetrics() {
        val now = SystemClock.elapsedRealtime()
        val elapsed = now - frameWindowStartMs
        if (elapsed >= 1_000) {
            _state.update {
                it.copy(
                    status = "외장 화면 전송 중",
                    framesPerSecond = (framesInWindow * 1_000L / elapsed).toInt(),
                    bitrateBitsPerSecond = bytesInWindow * 8_000L / elapsed,
                    lastFrameTimeMs = now
                )
            }
            frameWindowStartMs = now
            framesInWindow = 0
            bytesInWindow = 0
        } else {
            _state.update { it.copy(lastFrameTimeMs = now) }
        }
    }

    private fun resetMetrics(status: String, clearIdentity: Boolean) {
        frameWindowStartMs = SystemClock.elapsedRealtime()
        framesInWindow = 0
        bytesInWindow = 0
        _state.update {
            it.copy(
                status = status,
                codec = if (clearIdentity) null else it.codec,
                width = if (clearIdentity) null else it.width,
                height = if (clearIdentity) null else it.height,
                framesPerSecond = null,
                bitrateBitsPerSecond = null,
                lastFrameTimeMs = null,
                queueDepth = 0,
                droppedFrames = 0
            )
        }
    }

    private fun publishState(status: String?) {
        _state.update { it.copy(status = status ?: it.status, decoderState = machine.state) }
    }

    override fun onCleared() {
        receiver.stop()
        decoder.stop()
        machine.stop()
        super.onCleared()
    }

    class Factory(private val port: Int) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T = ExternalDisplayViewModel(port) as T
    }
}

private val VideoCodec.displayName: String get() = if (this == VideoCodec.H264) "H.264" else "HEVC"
