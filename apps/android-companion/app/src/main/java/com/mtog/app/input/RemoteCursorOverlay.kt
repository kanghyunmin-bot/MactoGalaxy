package com.mtog.app.input

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import kotlin.math.max
import kotlin.math.min

class RemoteCursorOverlay(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private val windowManager by lazy {
        context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    }

    private val cursorView = CursorView(context)
    private val layoutParams = WindowManager.LayoutParams(
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        android.graphics.PixelFormat.TRANSLUCENT
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        x = 0
        y = 0
    }

    @Volatile
    private var isAttached = false

    fun show(normalizedX: Float, normalizedY: Float, pressed: Boolean) {
        handler.post {
            val width = DisplayGeometry.currentWidth(context)
            val height = DisplayGeometry.currentHeight(context)
            val targetX = (width * normalizedX.coerceIn(0f, 1f)).toInt()
            val targetY = (height * normalizedY.coerceIn(0f, 1f)).toInt()
            layoutParams.x = targetX - cursorView.hotspotXPx
            layoutParams.y = targetY - cursorView.hotspotYPx
            cursorView.setPressedState(pressed)

            if (!isAttached) {
                windowManager.addView(cursorView, layoutParams)
                isAttached = true
            } else {
                windowManager.updateViewLayout(cursorView, layoutParams)
            }
        }
    }

    fun hide() {
        handler.post {
            if (!isAttached) {
                return@post
            }
            runCatching {
                windowManager.removeView(cursorView)
            }
            isAttached = false
        }
    }
}

private class CursorView(context: Context) : View(context) {
    private val density = resources.displayMetrics.density
    val desiredSizePx: Int = (min(DisplayGeometry.currentWidth(context), DisplayGeometry.currentHeight(context)) * 0.021f)
        .toInt()
        .coerceIn((15 * density).toInt(), (27 * density).toInt())
    val hotspotXPx: Int
        get() = (desiredSizePx * 0.06f).toInt()
    val hotspotYPx: Int
        get() = (desiredSizePx * 0.04f).toInt()

    private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x33000000
        style = Paint.Style.FILL
    }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        style = Paint.Style.STROKE
        strokeWidth = max(1.6f * density, 2f)
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
    }
    private val hotspotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x663A84FF
        style = Paint.Style.FILL
    }

    private var pressedState = false
    private val pointerPath = Path()
    private val shadowPath = Path()

    init {
        setLayerType(LAYER_TYPE_SOFTWARE, null)
    }

    fun setPressedState(pressed: Boolean) {
        pressedState = pressed
        alpha = if (pressed) 0.94f else 1f
        scaleX = if (pressed) 0.96f else 1f
        scaleY = if (pressed) 0.96f else 1f
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(desiredSizePx, desiredSizePx)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val size = width.toFloat()
        buildPointerPath(size)

        canvas.save()
        canvas.translate(2.8f * density, 3.4f * density)
        canvas.drawPath(shadowPath, shadowPaint)
        canvas.restore()

        canvas.drawPath(pointerPath, fillPaint)
        canvas.drawPath(pointerPath, strokePaint)

        if (pressedState) {
            canvas.drawCircle(size * 0.10f, size * 0.10f, size * 0.09f, hotspotPaint)
        }
    }

    private fun buildPointerPath(size: Float) {
        pointerPath.reset()
        pointerPath.moveTo(size * 0.06f, size * 0.04f)
        pointerPath.lineTo(size * 0.08f, size * 0.78f)
        pointerPath.lineTo(size * 0.27f, size * 0.60f)
        pointerPath.lineTo(size * 0.39f, size * 0.95f)
        pointerPath.lineTo(size * 0.51f, size * 0.90f)
        pointerPath.lineTo(size * 0.39f, size * 0.56f)
        pointerPath.lineTo(size * 0.67f, size * 0.56f)
        pointerPath.close()

        shadowPath.reset()
        shadowPath.addPath(pointerPath)
    }
}
