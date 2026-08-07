package com.lailanow

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import com.hiennv.flutter_callkit_incoming.CallkitEventCallback
import com.hiennv.flutter_callkit_incoming.CallkitNotificationManager
import com.hiennv.flutter_callkit_incoming.FlutterCallkitIncomingPlugin
import io.flutter.app.FlutterApplication

class MainApplication : FlutterApplication() {

    private val callEventCallback = object : CallkitEventCallback {
        override fun onCallEvent(event: CallkitEventCallback.CallEvent, callData: Bundle) {
            val accepted = event == CallkitEventCallback.CallEvent.ACCEPT
            RingtoneService.stop(this@MainApplication)
            IncomingCallActivity.dismiss(this@MainApplication, handled = accepted)
            CallkitBridge.cancelIncomingNotification(this@MainApplication, callData)
            CallLockscreen.setCallActive(accepted)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChatNotificationChannel()
        createCallkitOngoingChannel()
        disableCallkitFullScreenActivity()
        // Retries any decline that could not reach the backend earlier, so the
        // caller is not left ringing after a reject was lost offline.
        CallApi.flushPending(this)
        FlutterCallkitIncomingPlugin.registerEventCallback(callEventCallback)
    }

    private fun disableCallkitFullScreenActivity() {
        try {
            val component = ComponentName(
                this,
                "com.hiennv.flutter_callkit_incoming.CallkitIncomingActivity"
            )
            val current = packageManager.getComponentEnabledSetting(component)
            if (current != PackageManager.COMPONENT_ENABLED_STATE_DISABLED) {
                packageManager.setComponentEnabledSetting(
                    component,
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP
                )
            }
        } catch (e: Exception) {
            android.util.Log.d("MainApplication", "disableCallkitFullScreenActivity threw: $e")
        }
    }

    // Safety net: flutter_callkit_incoming's CallkitNotificationService calls
    // startForeground() with this channel whenever a call is accepted, but only
    // creates the channel in its own showIncomingCall / ACTION_CALL_START paths,
    // which this app replaces with IncomingCallActivity. A missing channel makes
    // startForeground() throw RemoteServiceException and kills the process, so the
    // channel is created up-front for every process that hosts the plugin.
    private fun createCallkitOngoingChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val manager = getSystemService(NotificationManager::class.java)
            val channelId = CallkitNotificationManager.NOTIFICATION_CHANNEL_ID_ONGOING
            if (manager.getNotificationChannel(channelId) != null) return
            val channel = NotificationChannel(
                channelId,
                "Ongoing Call",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            manager.createNotificationChannel(channel)
        } catch (e: Exception) {
            android.util.Log.d("MainApplication", "createCallkitOngoingChannel threw: $e")
        }
    }

    private fun createChatNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "chat_messages",
                "Chat Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "New chat messages"
                enableVibration(true)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}
