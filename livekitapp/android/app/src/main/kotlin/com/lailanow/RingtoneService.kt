package com.lailanow

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log

class RingtoneService : Service() {

    companion object {
        private const val TAG = "RingtoneService"
        private const val LEGACY_CHANNEL_ID = "ringtone_playback"
        private const val CHANNEL_ID = "ringtone_playback_silent"
        private const val NOTIFICATION_ID = 8811
        private const val MAX_RING_MS = 45_000L
        const val ACTION_START = "com.example.livekitapp.action.RINGTONE_START"
        const val ACTION_START_APP = "com.example.livekitapp.action.RINGTONE_START_APP"
        const val ACTION_STOP = "com.example.livekitapp.action.RINGTONE_STOP"

        fun stop(context: Context) {
            try {
                val intent = Intent(context.applicationContext, RingtoneService::class.java)
                intent.action = ACTION_STOP
                context.applicationContext.startService(intent)
            } catch (e: Exception) {
                Log.w(TAG, "stop threw: $e")
            }
        }
    }

    private var mediaPlayer: MediaPlayer? = null
    private var explicitlyStopped: Boolean = false
    private var callId: String = ""
    private var callerName: String = "Unknown"
    private var callType: String = "audio"
    private var callerPhotoUrl: String = ""
    private val timeoutHandler = Handler(Looper.getMainLooper())
    private val timeoutRunnable = Runnable {
        Log.d(TAG, "max ring duration reached, stopping")
        declineUnansweredCall()
        stopRinging()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun declineUnansweredCall() {
        if (callId.isEmpty()) return
        val app = applicationContext
        IncomingCallActivity.dismiss(app, handled = true)
        CallkitBridge.cancelIncomingNotification(app, CallkitBridge.callIdToUuid(callId))
        CallLockscreen.setCallActive(false)
        CallkitBridge.sendDecline(
            app,
            callId,
            CallkitBridge.buildCallBundle(callId, callerName, callType, callerPhotoUrl)
        )
        callId = ""
    }

    private fun readCall(intent: Intent) {
        callId = intent.getStringExtra(IncomingCallActivity.EXTRA_CALL_ID) ?: callId
        callerName = intent.getStringExtra(IncomingCallActivity.EXTRA_CALLER_NAME)
            ?.takeIf { it.isNotBlank() } ?: callerName
        callType = intent.getStringExtra(IncomingCallActivity.EXTRA_CALL_TYPE) ?: callType
        callerPhotoUrl =
            intent.getStringExtra(IncomingCallActivity.EXTRA_CALLER_PHOTO_URL) ?: callerPhotoUrl
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            when (intent?.action) {
                ACTION_STOP -> {
                    callId = ""
                    stopRinging()
                    explicitlyStopped = true
                    stopSelf()
                }
                ACTION_START_APP -> {
                    startForeground(NOTIFICATION_ID, buildNotification())
                    readCall(intent)
                    explicitlyStopped = false
                    startRinging()
                }
                else -> {
                    startForeground(NOTIFICATION_ID, buildNotification())
                    intent?.let { readCall(it) }
                    if (explicitlyStopped) {
                        Log.d(TAG, "onStartCommand: ignoring start, explicitly stopped")
                    } else {
                        startRinging()
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "onStartCommand failed: $e")
            try {
                startForeground(NOTIFICATION_ID, buildNotification())
            } catch (_: Exception) {}
        }
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            try {
                manager.deleteNotificationChannel(LEGACY_CHANNEL_ID)
            } catch (e: Exception) {
                Log.w(TAG, "deleteNotificationChannel threw: $e")
            }
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Ringtone Playback",
                NotificationManager.IMPORTANCE_MIN
            )
            channel.setSound(null, null)
            channel.enableVibration(false)
            channel.setShowBadge(false)
            channel.lockscreenVisibility = Notification.VISIBILITY_SECRET
            manager.createNotificationChannel(channel)
        }
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setVisibility(Notification.VISIBILITY_SECRET)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_MIN)
            .build()
    }

    private fun startRinging() {
        timeoutHandler.removeCallbacks(timeoutRunnable)
        timeoutHandler.postDelayed(timeoutRunnable, MAX_RING_MS)
        if (mediaPlayer != null) {
            Log.d(TAG, "startRinging: already ringing, ignoring duplicate start")
            return
        }
        try {
            val player = MediaPlayer()
            val afd = resources.openRawResourceFd(R.raw.ringtone_default)
            if (afd != null) {
                player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                afd.close()
            } else {
                Log.w(TAG, "No bundled default ringtone found")
                return
            }
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            player.isLooping = true
            player.setOnPreparedListener { it.start() }
            player.setOnErrorListener { _, what, extra ->
                Log.w(TAG, "MediaPlayer error what=$what extra=$extra")
                true
            }
            player.prepareAsync()
            mediaPlayer = player
        } catch (e: Exception) {
            Log.w(TAG, "startRinging failed: $e")
        }
    }

    private fun stopRinging() {
        timeoutHandler.removeCallbacks(timeoutRunnable)
        try {
            mediaPlayer?.let {
                if (it.isPlaying) it.stop()
                it.reset()
                it.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "stopRinging threw: $e")
        }
        mediaPlayer = null
    }

    override fun onDestroy() {
        stopRinging()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
