package com.mtog.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.mtog.app.service.SessionForegroundService

class ClipboardSyncActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private var syncAttempts = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        overridePendingTransition(0, 0)
    }

    override fun onResume() {
        super.onResume()
        syncAttempts = 0
        ContextCompat.startForegroundService(
            this,
            Intent(this, SessionForegroundService::class.java)
                .setAction(SessionForegroundService.actionStart)
        )
        handler.postDelayed({
            attemptClipboardSync()
        }, 220L)
    }

    override fun onPause() {
        handler.removeCallbacksAndMessages(null)
        super.onPause()
    }

    private fun attemptClipboardSync() {
        syncAttempts += 1
        val synced = SessionForegroundService.syncClipboardNow()
        if (!synced && syncAttempts < 4) {
            handler.postDelayed({ attemptClipboardSync() }, 180L)
            return
        }

        handler.postDelayed({
            finish()
            overridePendingTransition(0, 0)
        }, 120L)
    }
}
