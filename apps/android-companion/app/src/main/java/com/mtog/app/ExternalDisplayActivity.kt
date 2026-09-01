package com.mtog.app

import android.content.Intent
import android.graphics.RectF
import android.os.Bundle
import android.view.MotionEvent
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.lifecycle.lifecycleScope
import com.mtog.app.externaldisplay.DecoderState
import com.mtog.app.externaldisplay.ExternalDisplaySurface
import com.mtog.app.externaldisplay.ExternalDisplayTouchController
import com.mtog.app.externaldisplay.ExternalDisplayViewModel
import com.mtog.app.service.SessionForegroundService
import com.mtog.app.ui.theme.MtoGTheme

class ExternalDisplayActivity : ComponentActivity() {
    private val viewModel: ExternalDisplayViewModel by viewModels {
        ExternalDisplayViewModel.Factory(intent.getIntExtra("port", 46002))
    }
    private lateinit var touchController: ExternalDisplayTouchController
    private var notifiedStreaming = false
    @Volatile private var surfaceBounds = RectF()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        touchController = ExternalDisplayTouchController(lifecycleScope)
        touchController.start(intent.getIntExtra("inputPort", 46003))
        setContent {
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
        touchController.setEnabled(true)
        viewModel.resume()
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
