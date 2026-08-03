package com.example.livekitapp

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import com.hiennv.flutter_callkit_incoming.CallkitEventCallback
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
        disableCallkitFullScreenActivity()
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
