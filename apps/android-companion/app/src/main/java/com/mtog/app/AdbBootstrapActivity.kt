package com.mtog.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import androidx.core.content.ContextCompat
import com.mtog.app.service.SessionForegroundService

class AdbBootstrapActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        overridePendingTransition(0, 0)

        val serviceAction = when (intent?.action) {
            SessionForegroundService.actionSyncClipboard -> SessionForegroundService.actionSyncClipboard
            else -> SessionForegroundService.actionStart
        }
        ContextCompat.startForegroundService(
            this,
            Intent(this, SessionForegroundService::class.java).setAction(serviceAction)
        )

        finish()
        overridePendingTransition(0, 0)
    }
}
