package com.mtog.app

import android.content.Intent
import android.graphics.RectF
import android.os.Bundle
import android.view.MotionEvent
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.key
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.mtog.app.externaldisplay.DecoderState
import com.mtog.app.externaldisplay.ExternalDisplaySurface
import com.mtog.app.externaldisplay.ExternalDisplayTouchController
import com.mtog.app.externaldisplay.ExternalDisplayViewModel
import com.mtog.app.service.SessionForegroundService
import com.mtog.app.ui.theme.MtoGTheme
import java.util.UUID

class ExternalDisplayActivity : ComponentActivity() {
    private lateinit var controlSessionID: UUID
    private lateinit var viewModel: ExternalDisplayViewModel
    private lateinit var touchController: ExternalDisplayTouchController
    private var notifiedStreaming = false
    @Volatile private var surfaceBounds = RectF()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        hideSystemBars()
        installSession(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val replacementSession = sessionID(intent)
        if (replacementSession == controlSessionID) return

        touchController.stop()
        updateStreamingNotification(false)
        viewModelStore.clear()
        setIntent(intent)
        installSession(intent)
    }

    private fun installSession(intent: Intent) {
        controlSessionID = sessionID(intent)
        viewModel = ViewModelProvider(
            this,
            ExternalDisplayViewModel.Factory(intent.getIntExtra("port", 46002), controlSessionID)
        )[controlSessionID.toString(), ExternalDisplayViewModel::class.java]
        touchController = ExternalDisplayTouchController(lifecycleScope, controlSessionID)
        touchController.start(intent.getIntExtra("inputPort", 46003))
        surfaceBounds = RectF()
        setContent {
          key(controlSessionID) {
            MtoGTheme {
                val state by viewModel.state.collectAsState()
                LaunchedEffect(state.decoderState) {
                    updateStreamingNotification(state.decoderState == DecoderState.Streaming)
                }
                ExternalDisplaySurface(
                    state = state,
                    onSurfaceAvailable = viewModel::onSurfaceAvailable,
                    onSurfaceLost = viewModel::onSurfaceLost,
                    onSurfaceBoundsChanged = { surfaceBounds = it }
                )
            }
          }
        }
    }

    private fun sessionID(intent: Intent): UUID =
        requireNotNull(intent.getStringExtra("sessionId")?.let(UUID::fromString))

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (touchController.handle(event, surfaceBounds)) return true
        return super.dispatchTouchEvent(event)
    }

    override fun onPause() {
        touchController.setEnabled(false)
        viewModel.pause()
        updateStreamingNotification(false)
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        hideSystemBars()
        touchController.setEnabled(true)
        viewModel.resume()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    private fun hideSystemBars() {
        WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
    }

    private fun updateStreamingNotification(streaming: Boolean) {
        if (streaming == notifiedStreaming) return
        notifiedStreaming = streaming
        val action = if (streaming) {
            SessionForegroundService.actionStartStreaming
        } else {
            SessionForegroundService.actionStopStreaming
        }
        startService(Intent(this, SessionForegroundService::class.java).setAction(action))
    }

    override fun onDestroy() {
        touchController.stop()
        updateStreamingNotification(false)
        super.onDestroy()
    }
}
