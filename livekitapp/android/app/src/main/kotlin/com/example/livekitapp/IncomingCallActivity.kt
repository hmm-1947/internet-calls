package com.example.livekitapp

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.TextView

class IncomingCallActivity : Activity() {

    companion object {
        const val EXTRA_CALL_ID = "call_id"
        const val EXTRA_CALLER_NAME = "caller_name"
        const val EXTRA_CALL_TYPE = "call_type"
        const val EXTRA_CALLER_PHOTO_URL = "caller_photo_url"
        const val ACTION_DISMISS = "com.example.livekitapp.action.DISMISS_INCOMING_CALL"
        const val EXTRA_HANDLED = "handled"

        private const val CHANNEL_ID = "incoming_call_lockscreen"
        private const val NOTIFICATION_ID = 8812
        private const val AUTO_DISMISS_MS = 45_000L
        private const val SWEEP_INTERVAL_MS = 400L
        private const val FAST_SWEEP_MS = 120L
        private const val FAST_SWEEP_WINDOW_MS = 8_000L
        private const val ACCEPT_CLOSE_DELAY_MS = 150L

        fun getIntent(
            context: Context,
            callId: String,
            callerName: String,
            callType: String,
            callerPhotoUrl: String
        ): Intent = Intent(context, IncomingCallActivity::class.java).apply {
            putExtra(EXTRA_CALL_ID, callId)
            putExtra(EXTRA_CALLER_NAME, callerName)
            putExtra(EXTRA_CALL_TYPE, callType)
            putExtra(EXTRA_CALLER_PHOTO_URL, callerPhotoUrl)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_NO_USER_ACTION or
                    Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
            )
        }

        fun show(
            context: Context,
            callId: String,
            callerName: String,
            callType: String,
            callerPhotoUrl: String,
            fullScreen: Boolean
        ) {
            val app = context.applicationContext
            val photoUrl = AvatarLoader.resolveUrl(app, callerPhotoUrl)
            notify(app, callId, callerName, callType, photoUrl, AvatarLoader.cached(app, photoUrl))
            if (photoUrl.isNotEmpty()) {
                AvatarLoader.load(app, photoUrl) { bitmap ->
                    notify(app, callId, callerName, callType, photoUrl, bitmap)
                }
            }
            if (!fullScreen) return
            try {
                app.startActivity(getIntent(app, callId, callerName, callType, photoUrl))
            } catch (e: Exception) {
                android.util.Log.d("IncomingCall", "startActivity threw: $e")
            }
        }

        fun showOverLockscreen(
            context: Context,
            callId: String,
            callerName: String,
            callType: String,
            callerPhotoUrl: String
        ) = show(context, callId, callerName, callType, callerPhotoUrl, fullScreen = true)

        private fun notify(
            context: Context,
            callId: String,
            callerName: String,
            callType: String,
            callerPhotoUrl: String,
            avatar: Bitmap?
        ) {
            createChannel(context)
            val notification =
                buildNotification(context, callId, callerName, callType, callerPhotoUrl, avatar)
            try {
                val manager =
                    context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(NOTIFICATION_ID, notification)
            } catch (e: Exception) {
                android.util.Log.d("IncomingCall", "notify threw: $e")
            }
        }

        private fun buildNotification(
            context: Context,
            callId: String,
            callerName: String,
            callType: String,
            callerPhotoUrl: String,
            avatar: Bitmap?
        ): Notification {
            val fullScreenIntent = PendingIntent.getActivity(
                context,
                NOTIFICATION_ID,
                getIntent(context, callId, callerName, callType, callerPhotoUrl),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val acceptIntent = PendingIntent.getBroadcast(
                context,
                NOTIFICATION_ID + 1,
                CallActionReceiver.intentFor(
                    context,
                    CallActionReceiver.ACTION_ACCEPT,
                    callId,
                    callerName,
                    callType,
                    callerPhotoUrl
                ),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            val declineIntent = PendingIntent.getBroadcast(
                context,
                NOTIFICATION_ID + 2,
                CallActionReceiver.intentFor(
                    context,
                    CallActionReceiver.ACTION_DECLINE,
                    callId,
                    callerName,
                    callType,
                    callerPhotoUrl
                ),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            val label = if (callType == "video") "Incoming video call" else "Incoming call"
            builder
                .setContentTitle(callerName)
                .setContentText(label)
                .setSmallIcon(context.applicationInfo.icon)
                .setCategory(Notification.CATEGORY_CALL)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .setSound(null)
                .setVibrate(null)
                .setFullScreenIntent(fullScreenIntent, true)
                .setContentIntent(fullScreenIntent)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                builder.setTimeoutAfter(AUTO_DISMISS_MS)
            }

            if (avatar != null) {
                builder.setLargeIcon(avatar)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val person = Person.Builder()
                    .setName(callerName)
                    .setImportant(true)
                    .apply { if (avatar != null) setIcon(Icon.createWithBitmap(avatar)) }
                    .build()
                builder.setStyle(
                    Notification.CallStyle
                        .forIncomingCall(person, declineIntent, acceptIntent)
                        .setIsVideo(callType == "video")
                )
            } else {
                builder.addAction(
                    Notification.Action.Builder(
                        Icon.createWithResource(context, R.drawable.ic_call_end),
                        context.getString(R.string.incoming_call_decline),
                        declineIntent
                    ).build()
                )
                builder.addAction(
                    Notification.Action.Builder(
                        Icon.createWithResource(context, R.drawable.ic_call),
                        context.getString(R.string.incoming_call_accept),
                        acceptIntent
                    ).build()
                )
            }
            return builder.build()
        }

        fun cancelNotification(context: Context) {
            try {
                val manager =
                    context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.cancel(NOTIFICATION_ID)
            } catch (e: Exception) {
                android.util.Log.d("IncomingCall", "cancel threw: $e")
            }
        }

        @JvmOverloads
        fun dismiss(context: Context, handled: Boolean = false) {
            cancelNotification(context)
            try {
                context.sendBroadcast(
                    Intent(ACTION_DISMISS)
                        .setPackage(context.packageName)
                        .putExtra(EXTRA_HANDLED, handled)
                )
            } catch (e: Exception) {
                android.util.Log.d("IncomingCall", "dismiss broadcast threw: $e")
            }
        }

        private fun createChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            try {
                val manager =
                    context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Incoming Call Screen",
                    NotificationManager.IMPORTANCE_HIGH
                )
                channel.setSound(null, null)
                channel.enableVibration(false)
                channel.setShowBadge(false)
                channel.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                manager.createNotificationChannel(channel)
            } catch (e: Exception) {
                android.util.Log.d("IncomingCall", "createChannel threw: $e")
            }
        }
    }

    private var callId: String = ""
    private var callerName: String = "Unknown"
    private var callType: String = "audio"
    private var callerPhotoUrl: String = ""
    private var handled = false

    private val autoDismiss = Handler(Looper.getMainLooper())
    private val autoDismissRunnable = Runnable { onTimeout() }

    private var sweepStartedAt = 0L

    private val notificationSweeper = object : Runnable {
        override fun run() {
            clearCallkitNotification()
            val elapsed = android.os.SystemClock.elapsedRealtime() - sweepStartedAt
            val next = if (elapsed < FAST_SWEEP_WINDOW_MS) FAST_SWEEP_MS else SWEEP_INTERVAL_MS
            autoDismiss.postDelayed(this, next)
        }
    }

    private val dismissReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.getBooleanExtra(EXTRA_HANDLED, false)) handled = true
            if (handled) {
                finishScreen()
                return
            }
            closeScreen()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CallLockscreen.apply(this, true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContentView(R.layout.activity_incoming_call)
        readIntent(intent)
        bindView()
        registerDismissReceiver()
        autoDismiss.postDelayed(autoDismissRunnable, AUTO_DISMISS_MS)
        sweepStartedAt = android.os.SystemClock.elapsedRealtime()
        notificationSweeper.run()
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        if (intent == null) return
        setIntent(intent)
        readIntent(intent)
        bindView()
    }

    private fun readIntent(intent: Intent) {
        callId = intent.getStringExtra(EXTRA_CALL_ID) ?: callId
        callerName = intent.getStringExtra(EXTRA_CALLER_NAME)?.takeIf { it.isNotBlank() }
            ?: callerName
        callType = intent.getStringExtra(EXTRA_CALL_TYPE) ?: callType
        callerPhotoUrl = AvatarLoader.resolveUrl(
            this,
            intent.getStringExtra(EXTRA_CALLER_PHOTO_URL) ?: callerPhotoUrl
        )
    }

    private fun bindView() {
        findViewById<TextView>(R.id.tvCallerName).text = callerName
        findViewById<TextView>(R.id.tvCallSubtitle).text =
            if (callType == "video") "Incoming video call" else "Incoming call"
        findViewById<TextView>(R.id.tvCallerInitial).text = initialOf(callerName)
        findViewById<View>(R.id.ivAccept).setOnClickListener { onAccept() }
        findViewById<View>(R.id.ivDecline).setOnClickListener { onDecline() }
        bindAvatar()
    }

    private fun bindAvatar() {
        val photo = findViewById<ImageView>(R.id.ivCallerPhoto)
        photo.visibility = View.GONE
        if (callerPhotoUrl.isEmpty()) return
        AvatarLoader.load(this, callerPhotoUrl) { bitmap ->
            if (isFinishing || isDestroyed) return@load
            photo.setImageBitmap(bitmap)
            photo.visibility = View.VISIBLE
        }
    }

    private fun clearCallkitNotification() {
        if (callId.isEmpty()) return
        CallkitBridge.cancelIncomingNotification(this, CallkitBridge.callIdToUuid(callId))
    }

    private fun initialOf(name: String): String {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return "?"
        return trimmed.substring(0, 1).uppercase()
    }

    private fun registerDismissReceiver() {
        val filter = IntentFilter(ACTION_DISMISS)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(dismissReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(dismissReceiver, filter)
        }
    }

    private fun onAccept() {
        if (handled) return
        handled = true
        autoDismiss.removeCallbacksAndMessages(null)
        stopRingtone()
        cancelNotification(this)
        clearCallkitNotification()
        CallLockscreen.setCallActive(true)
        val data = CallkitBridge.buildCallBundle(callId, callerName, callType, callerPhotoUrl)
        CallkitBridge.openCallScreen(this)
        CallkitBridge.sendAccept(applicationContext, data)
        autoDismiss.postDelayed({ finishScreen() }, ACCEPT_CLOSE_DELAY_MS)
    }

    private fun onDecline() {
        if (handled) return
        handled = true
        stopRingtone()
        cancelNotification(this)
        clearCallkitNotification()
        val data = CallkitBridge.buildCallBundle(callId, callerName, callType, callerPhotoUrl)
        CallkitBridge.sendDecline(applicationContext, data)
        CallLockscreen.setCallActive(false)
        finishScreen()
    }

    private fun onTimeout() {
        if (handled) {
            finishScreen()
            return
        }
        handled = true
        stopRingtone()
        cancelNotification(this)
        clearCallkitNotification()
        val data = CallkitBridge.buildCallBundle(callId, callerName, callType, callerPhotoUrl)
        CallkitBridge.sendDecline(applicationContext, data)
        CallLockscreen.setCallActive(false)
        finishScreen()
    }

    private fun stopRingtone() {
        try {
            val intent = Intent(applicationContext, RingtoneService::class.java)
            intent.action = RingtoneService.ACTION_STOP
            applicationContext.startService(intent)
        } catch (e: Exception) {
            android.util.Log.d("IncomingCall", "stopRingtone threw: $e")
        }
    }

    private fun closeScreen() {
        if (!handled) {
            stopRingtone()
            CallLockscreen.setCallActive(false)
        }
        finishScreen()
    }

    private fun finishScreen() {
        autoDismiss.removeCallbacksAndMessages(null)
        if (isFinishing) return
        finish()
        overridePendingTransition(0, 0)
    }

    @Deprecated("Blocked so the lock screen cannot be bypassed")
    override fun onBackPressed() {
    }

    override fun onDestroy() {
        autoDismiss.removeCallbacksAndMessages(null)
        try {
            unregisterReceiver(dismissReceiver)
        } catch (e: Exception) {
            android.util.Log.d("IncomingCall", "unregisterReceiver threw: $e")
        }
        if (!handled) {
            cancelNotification(this)
        }
        super.onDestroy()
    }
}
