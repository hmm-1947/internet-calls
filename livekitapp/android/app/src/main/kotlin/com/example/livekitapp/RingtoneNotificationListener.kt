package com.example.livekitapp

import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

class RingtoneNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "RingtoneNotifListener"
        private const val OWN_CHANNEL_ID = "ringtone_playback"
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return
        if (sbn.packageName != packageName) return
        if (sbn.notification.channelId == OWN_CHANNEL_ID) return
        try {
            val extras = sbn.notification.extras
            val title = extras?.getCharSequence("android.title")?.toString() ?: ""
            val text = extras?.getCharSequence("android.text")?.toString() ?: ""
            val isOngoing = (sbn.notification.flags and android.app.Notification.FLAG_ONGOING_EVENT) != 0
            Log.d(TAG, "onNotificationPosted title=$title text=$text ongoing=$isOngoing")
            if (isOngoing) {
                val intent = Intent(this, RingtoneService::class.java)
                intent.action = RingtoneService.ACTION_START
                startForegroundService(intent)
            }
        } catch (e: Exception) {
            Log.w(TAG, "onNotificationPosted failed: $e")
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        if (sbn == null) return
        if (sbn.packageName != packageName) return
        if (sbn.notification.channelId == OWN_CHANNEL_ID) return
        try {
            Log.d(TAG, "onNotificationRemoved for our package, stopping ringtone")
            val intent = Intent(this, RingtoneService::class.java)
            intent.action = RingtoneService.ACTION_STOP
            startService(intent)
        } catch (e: Exception) {
            Log.w(TAG, "onNotificationRemoved failed: $e")
        }
    }
}
