package com.mtog.app

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.mtog.app.service.SessionForegroundService

/** The system shares a temporary URI grant with this foreground activity. */
class ShareToMacActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 48, 32, 32)
        }
        val status = TextView(this).apply {
            text = "사진·파일·텍스트를 Mac으로 공유합니다. 먼저 Mac에서 USB 연결하세요. 파일은 항목당 최대 24MB입니다."
            textSize = 18f
        }
        layout.addView(status)
        layout.addView(Button(this).apply {
            text = "클립보드에 복사하고 Mac으로 보내기"
            setOnClickListener {
                val clip = sharedClip()
                if (clip == null) {
                    status.text = "지원하지 않는 공유 항목입니다. 사진이나 파일을 하나 선택하세요."
                    return@setOnClickListener
                }
                try {
                    getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
                    status.text = if (SessionForegroundService.syncClipboardNow()) {
                        "Mac으로 전송을 요청했습니다. Mac에서 수신 상태를 확인하세요."
                    } else {
                        "클립보드에 복사했습니다. Mac의 USB 연결을 확인한 뒤 다시 보내세요."
                    }
                } catch (_: SecurityException) {
                    status.text = "파일 읽기 권한이 만료됐습니다. 원래 앱에서 다시 공유하세요."
                }
            }
        })
        layout.addView(Button(this).apply { text = "닫기"; setOnClickListener { finish() } })
        setContentView(layout)
    }

    @Suppress("DEPRECATION")
    private fun sharedClip(): ClipData? {
        if (intent.action != Intent.ACTION_SEND) return null
        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        if (uri != null) {
            if (uri.scheme != "content") return null
            return ClipData.newUri(contentResolver, "MtoG 공유", uri)
        }
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() ?: return null
        if (text.isEmpty() || text.toByteArray(Charsets.UTF_8).size > 262130) return null
        return ClipData.newPlainText("MtoG 공유", text)
    }
}
