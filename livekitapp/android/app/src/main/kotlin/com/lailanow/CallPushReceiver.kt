package com.lailanow

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class CallPushReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        when (extras.getString("type")) {
            "call" -> onIncomingCall(context.applicationContext, extras)
            "call_cancelled", "call_ended", "call_rejected" ->
                onCallGone(context.applicationContext)
        }
    }

    private fun onIncomingCall(context: Context, extras: android.os.Bundle) {
        if (!CallApi.hasAuthToken(context)) return
        val callId = extras.getString("call_id") ?: return
        val callerName = extras.getString("caller_name")?.takeIf { it.isNotBlank() } ?: "Unknown"
        val callType = extras.getString("call_type") ?: "audio"
        val callerPhotoUrl = extras.getString("caller_photo_url") ?: ""

        CallLockscreen.setCallActive(true)
        startRingtone(context, callId, callerName, callType, callerPhotoUrl)

        val locked = CallLockscreen.isDeviceLocked(context)
        val screenOff = !CallLockscreen.isDeviceInteractive(context)

        IncomingCallActivity.show(
            context,
            callId,
            callerName,
            callType,
            callerPhotoUrl,
            fullScreen = locked || screenOff
        )
    }

    private fun onCallGone(context: Context) {
        CallLockscreen.setCallActive(false)
        IncomingCallActivity.dismiss(context)
        stopRingtone(context)
    }

    private fun startRingtone(
        context: Context,
        callId: String,
        callerName: String,
        callType: String,
        callerPhotoUrl: String
    ) {
        try {
            val intent = Intent(context, RingtoneService::class.java)
            intent.action = RingtoneService.ACTION_START_APP
            intent.putExtra(IncomingCallActivity.EXTRA_CALL_ID, callId)
            intent.putExtra(IncomingCallActivity.EXTRA_CALLER_NAME, callerName)
            intent.putExtra(IncomingCallActivity.EXTRA_CALL_TYPE, callType)
            intent.putExtra(IncomingCallActivity.EXTRA_CALLER_PHOTO_URL, callerPhotoUrl)
            context.startForegroundService(intent)
        } catch (e: Exception) {
            android.util.Log.d("CallPushReceiver", "startRingtone threw: $e")
        }
    }

    private fun stopRingtone(context: Context) {
        try {
            val intent = Intent(context, RingtoneService::class.java)
            intent.action = RingtoneService.ACTION_STOP
            context.startService(intent)
        } catch (e: Exception) {
            android.util.Log.d("CallPushReceiver", "stopRingtone threw: $e")
        }
    }
}
