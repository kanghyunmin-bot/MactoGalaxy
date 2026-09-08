package com.mtog.app.externaldisplay

import android.graphics.RectF
import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView

@Composable
fun ExternalDisplaySurface(
    state: ExternalDisplayUiState,
    onSurfaceAvailable: (android.view.Surface) -> Unit,
    onSurfaceLost: () -> Unit,
    onSurfaceBoundsChanged: (RectF) -> Unit
) {
    val context = LocalContext.current
    Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
        val aspectRatio = (state.width ?: 1920).toFloat() / (state.height ?: 1200).coerceAtLeast(1)
        AndroidView(
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .aspectRatio(aspectRatio)
                .onGloballyPositioned { coordinates ->
                    val position = coordinates.positionInWindow()
                    onSurfaceBoundsChanged(
                        RectF(
                            position.x,
                            position.y,
                            position.x + coordinates.size.width,
                            position.y + coordinates.size.height
                        )
                    )
                },
            factory = {
                SurfaceView(context).apply {
                    contentDescription = "Mac 외장 화면 영상"
                    holder.addCallback(object : SurfaceHolder.Callback {
                        override fun surfaceCreated(holder: SurfaceHolder) = onSurfaceAvailable(holder.surface)
                        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit
                        override fun surfaceDestroyed(holder: SurfaceHolder) = onSurfaceLost()
                    })
                }
            }
        )
        if (state.decoderState != DecoderState.Streaming) {
            Column(
                modifier = Modifier
                    .align(Alignment.Center)
                    .background(Color(0xCC101820))
                    .padding(horizontal = 24.dp, vertical = 18.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text("MtoG 외장 화면", style = MaterialTheme.typography.headlineSmall, color = Color.White)
                Text(state.status, color = Color.White.copy(alpha = 0.78f))
            }
        }
    }
}
