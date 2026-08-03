package com.example.livekitapp

import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver
import com.hiennv.flutter_callkit_incoming.Data

object CallkitBridge {

    fun callIdToUuid(callId: String): String =
        "00000000-0000-0000-0000-" + callId.padStart(12, '0')

    fun buildCallBundle(
        callId: String,
        callerName: String,
        callType: String,
        callerPhotoUrl: String
    ): Bundle {
        val extra = HashMap<String, Any?>()
        extra["call_id"] = callId
        extra["caller_name"] = callerName
        extra["call_type"] = callType
        extra["caller_photo_url"] = callerPhotoUrl

        val android = HashMap<String, Any?>()
        android["isCustomNotification"] = true
        android["isShowLogo"] = false
        android["ringtonePath"] = "silent_ring"
        android["backgroundColor"] = "#0B0F1A"
        android["actionColor"] = "#E53950"
        android["incomingCallNotificationChannelName"] = "Incoming Call"
        android["isShowFullLockedScreen"] = false
        android["isFullScreen"] = false

        val args = HashMap<String, Any?>()
        args["id"] = callIdToUuid(callId)
        args["nameCaller"] = callerName
        args["appName"] = "Listener App"
        args["handle"] = callerName
        args["avatar"] = ""
        args["type"] = 0
        args["duration"] = 30000L
        args["extra"] = extra
        args["android"] = android

        return Data(args).toBundle()
    }

    fun cancelIncomingNotification(context: Context, data: Bundle) {
        val id = try {
            Data.fromBundle(data).id
        } catch (e: Exception) {
            ""
        }
        if (id.isEmpty()) return
        cancelIncomingNotification(context, id)
    }

    fun cancelIncomingNotification(context: Context, uuid: String) {
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as android.app.NotificationManager
            manager.cancel(uuid.hashCode())
        } catch (e: Exception) {
            android.util.Log.d("CallkitBridge", "cancelIncomingNotification threw: $e")
        }
    }

    fun openCallScreen(context: Context) {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            setClassName(context.packageName, MainActivity::class.java.name)
            addCategory(Intent.CATEGORY_LAUNCHER)
            putExtra(MainActivity.EXTRA_OPEN_ACTIVE_CALL, true)
            putExtra(MainActivity.EXTRA_FROM_LOCKSCREEN, true)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            android.util.Log.d("CallkitBridge", "openCallScreen threw: $e")
        }
    }

    fun sendAccept(context: Context, data: Bundle) {
        send(context, CallkitIncomingBroadcastReceiver.getIntentAccept(context, data))
    }

    fun sendDecline(context: Context, data: Bundle) {
        send(context, CallkitIncomingBroadcastReceiver.getIntentDecline(context, data))
    }

    private fun send(context: Context, intent: Intent) {
        try {
            intent.addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
            context.sendBroadcast(intent)
        } catch (e: Exception) {
            android.util.Log.d("CallkitBridge", "sendBroadcast threw: $e")
        }
    }
}
