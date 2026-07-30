package com.example.livekitapp

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.IBinder
import android.util.Log

class RingtoneService : Service() {

    companion object {
        private const val TAG = "RingtoneService"
        private const val CHANNEL_ID = "ringtone_playback"
        private const val NOTIFICATION_ID = 8811
        const val ACTION_START = "com.example.livekitapp.action.RINGTONE_START"
        const val ACTION_START_APP = "com.example.livekitapp.action.RINGTONE_START_APP"
        const val ACTION_STOP = "com.example.livekitapp.action.RINGTONE_STOP"
    }

    private var mediaPlayer: MediaPlayer? = null
    private var explicitlyStopped: Boolean = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            when (intent?.action) {
                ACTION_STOP -> {
                    stopRinging()
                    explicitlyStopped = true
                    stopSelf()
                }
                ACTION_START_APP -> {
                    startForeground(NOTIFICATION_ID, buildNotification())
                    explicitlyStopped = false
                    startRinging()
                }
                else -> {
                    startForeground(NOTIFICATION_ID, buildNotification())
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
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Ringtone Playback",
                NotificationManager.IMPORTANCE_LOW
            )
            manager.createNotificationChannel(channel)
        }
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Incoming call")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .build()
    }

    private fun startRinging() {
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
