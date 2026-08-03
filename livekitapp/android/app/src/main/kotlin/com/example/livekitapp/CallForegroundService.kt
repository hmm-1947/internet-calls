package com.example.livekitapp

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class CallForegroundService : Service() {

    companion object {
        private const val TAG = "CallForegroundService"
        private const val CHANNEL_ID = "active_call"
        private const val NOTIFICATION_ID = 9911
        const val ACTION_START = "com.example.livekitapp.action.CALL_FG_START"
        const val ACTION_STOP = "com.example.livekitapp.action.CALL_FG_STOP"
        const val ACTION_HANG_UP = "com.example.livekitapp.action.CALL_FG_HANG_UP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_VIDEO = "video"
    }

    private var callStartedAt = 0L
    private var currentTitle = "Ongoing call"
    private var withCamera = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        when (intent.action) {
            ACTION_STOP -> {
                callStartedAt = 0L
                withCamera = false
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_HANG_UP -> {
                goForeground()
                val engine = FlutterEngineCache.getInstance().get(MainActivity.ENGINE_ID)
                if (engine == null) {
                    callStartedAt = 0L
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                } else {
                    MethodChannel(
                        engine.dartExecutor.binaryMessenger,
                        MainActivity.CALL_FG_CHANNEL
                    ).invokeMethod("hangUpActiveCall", null)
                }
            }
            else -> {
                currentTitle = intent.getStringExtra(EXTRA_TITLE) ?: currentTitle
                withCamera = intent.getBooleanExtra(EXTRA_VIDEO, withCamera)
                if (callStartedAt == 0L) callStartedAt = System.currentTimeMillis()
                goForeground()
            }
        }
        return START_NOT_STICKY
    }

    private fun goForeground() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            try {
                startForeground(NOTIFICATION_ID, buildNotification(currentTitle))
            } catch (e: Exception) {
                Log.w(TAG, "startForeground failed: $e")
            }
            return
        }
        val baseTypes = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
            ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
        val types = if (withCamera) {
            baseTypes or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        } else {
            baseTypes
        }
        try {
            startForeground(NOTIFICATION_ID, buildNotification(currentTitle), types)
            return
        } catch (e: Exception) {
            Log.w(TAG, "startForeground with types=$types failed: $e")
        }
        try {
            startForeground(
                NOTIFICATION_ID,
                buildNotification(currentTitle),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
            )
            return
        } catch (e: Exception) {
            Log.w(TAG, "startForeground phoneCall fallback failed: $e")
        }
        try {
            startForeground(NOTIFICATION_ID, buildNotification(currentTitle))
        } catch (e: Exception) {
            Log.w(TAG, "startForeground untyped fallback failed: $e")
        }
    }

    private fun buildNotification(title: String): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Active Call",
                NotificationManager.IMPORTANCE_LOW
            )
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }

        val openIntent = Intent(Intent.ACTION_MAIN).apply {
            setClassName(packageName, MainActivity::class.java.name)
            addCategory(Intent.CATEGORY_LAUNCHER)
            putExtra(MainActivity.EXTRA_OPEN_ACTIVE_CALL, true)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val hangUpIntent = Intent(this, CallForegroundService::class.java).apply {
            action = ACTION_HANG_UP
        }
        val hangUpPendingIntent = PendingIntent.getService(
            this,
            1,
            hangUpIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText("Tap to return to call")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setShowWhen(true)
            .setWhen(if (callStartedAt == 0L) System.currentTimeMillis() else callStartedAt)
            .setUsesChronometer(true)
            .setContentIntent(contentIntent)
            .addAction(
                Notification.Action.Builder(
                    android.graphics.drawable.Icon.createWithResource(
                        this,
                        android.R.drawable.ic_menu_close_clear_cancel
                    ),
                    "End call",
                    hangUpPendingIntent
                ).build()
            )

        return builder.build()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "onTaskRemoved: keeping the call alive")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
