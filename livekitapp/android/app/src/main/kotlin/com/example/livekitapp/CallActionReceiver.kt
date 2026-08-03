package com.example.livekitapp

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class CallActionReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_ACCEPT = "com.example.livekitapp.action.NOTIFICATION_CALL_ACCEPT"
        const val ACTION_DECLINE = "com.example.livekitapp.action.NOTIFICATION_CALL_DECLINE"

        fun intentFor(
            context: Context,
            action: String,
            callId: String,
            callerName: String,
            callType: String,
            callerPhotoUrl: String
        ): Intent = Intent(context, CallActionReceiver::class.java).apply {
            this.action = action
            setPackage(context.packageName)
            putExtra(IncomingCallActivity.EXTRA_CALL_ID, callId)
            putExtra(IncomingCallActivity.EXTRA_CALLER_NAME, callerName)
            putExtra(IncomingCallActivity.EXTRA_CALL_TYPE, callType)
            putExtra(IncomingCallActivity.EXTRA_CALLER_PHOTO_URL, callerPhotoUrl)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        val callId = intent.getStringExtra(IncomingCallActivity.EXTRA_CALL_ID) ?: return
        val callerName = intent.getStringExtra(IncomingCallActivity.EXTRA_CALLER_NAME) ?: "Unknown"
        val callType = intent.getStringExtra(IncomingCallActivity.EXTRA_CALL_TYPE) ?: "audio"
        val photoUrl = intent.getStringExtra(IncomingCallActivity.EXTRA_CALLER_PHOTO_URL) ?: ""

        RingtoneService.stop(app)
        IncomingCallActivity.cancelNotification(app)
        CallkitBridge.cancelIncomingNotification(app, CallkitBridge.callIdToUuid(callId))

        val data = CallkitBridge.buildCallBundle(callId, callerName, callType, photoUrl)
        when (intent.action) {
            ACTION_ACCEPT -> {
                CallLockscreen.setCallActive(true)
                IncomingCallActivity.dismiss(app, handled = true)
                CallkitBridge.openCallScreen(app)
                CallkitBridge.sendAccept(app, data)
            }
            ACTION_DECLINE -> {
                CallLockscreen.setCallActive(false)
                IncomingCallActivity.dismiss(app, handled = true)
                CallkitBridge.sendDecline(app, data)
            }
        }
    }
}
