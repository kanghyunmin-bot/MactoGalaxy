package com.mtog.app.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.mtog.app.MainActivity
import com.mtog.app.clipboard.ClipboardHistoryStore
import com.mtog.app.pairing.PairingStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import java.lang.ref.WeakReference

class SessionForegroundService : Service() {
    companion object {
        const val actionStart = "com.mtog.app.service.START"
        const val actionStop = "com.mtog.app.service.STOP"
        const val actionSyncClipboard = "com.mtog.app.service.SYNC_CLIPBOARD"

        private const val channelId = "mtog_session"
        private const val notificationId = 46001

        private var activeServiceRef: WeakReference<SessionForegroundService>? = null

        fun syncClipboardNow(): Boolean {
            return activeServiceRef?.get()?.syncClipboardNowInternal() == true
        }
    }

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private lateinit var adbLoopbackServer: AdbLoopbackServer

    override fun onCreate() {
        super.onCreate()
        ClipboardHistoryStore.initialize(applicationContext)
        PairingStore.initialize(applicationContext)
        adbLoopbackServer = AdbLoopbackServer(applicationContext, serviceScope)
        activeServiceRef = WeakReference(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action ?: actionStart) {
            actionStop -> {
                adbLoopbackServer.stop()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            actionSyncClipboard -> {
                startSessionServer()
                syncClipboardNowInternal()
            }
            else -> startSessionServer()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        adbLoopbackServer.stop()
        stopForeground(STOP_FOREGROUND_REMOVE)
        serviceScope.cancel()
        activeServiceRef?.clear()
        activeServiceRef = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startSessionServer() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(notificationId, notification)
        }
        adbLoopbackServer.start()
    }

    private fun syncClipboardNowInternal(): Boolean {
        startSessionServer()
        return adbLoopbackServer.syncCurrentClipboard()
    }

    private fun buildNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val clipboardSyncIntent = Intent(this, com.mtog.app.ClipboardSyncActivity::class.java)
            .setAction(MainActivity.actionSyncClipboard)
        val clipboardSyncPendingIntent = PendingIntent.getActivity(
            this,
            1,
            clipboardSyncIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("MtoG manual clipboard")
            .setContentText("Copy on Galaxy, then tap Sync Clipboard to send it to Mac.")
            .setContentIntent(pendingIntent)
            .addAction(
                android.R.drawable.ic_menu_upload,
                "Sync Clipboard",
                clipboardSyncPendingIntent
            )
            .setOngoing(true)
        return builder.build()
    }

    private fun createNotificationChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            channelId,
            "MtoG Session",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Manual clipboard sync and trusted Mac session listener"
        }
        manager.createNotificationChannel(channel)
    }
}
